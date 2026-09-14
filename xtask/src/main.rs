//! `cargo xtask` keeps pull-managed Homebrew formulas reproducible from an
//! explicit release tag and recorded archive digests. It has no discovery or
//! VCS behavior: an agent chooses a release, and this command validates bytes.

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::{self, Cursor, Read, Write},
    path::{Component, Path, PathBuf},
    time::Duration,
};

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Parser, Subcommand};
use reqwest::{Url, blocking::Client, redirect::Policy};
use semver::Version;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tar::{Archive, EntryType};
use tempfile::Builder as TempBuilder;
use tracing::{debug, info};
use xz2::stream::Stream;

const TARGETS: [&str; 4] = [
    "aarch64-apple-darwin",
    "aarch64-unknown-linux-gnu",
    "x86_64-apple-darwin",
    "x86_64-unknown-linux-gnu",
];
const MAX_COMPRESSED: u64 = 64 * 1024 * 1024;
const MAX_EXPANDED: u64 = 256 * 1024 * 1024;
const MAX_ENTRIES: usize = 1024;

/// Everything the updater knows about one tool: where its releases live and
/// what the rendered formula says about it.
///
/// Both registered tools publish with dist, whose archive layout is identical
/// for them (`<name>-<target>/{README.md,CHANGELOG.md,LICENSE,<name>}`), so
/// the archive contract is shared and only these values differ. A tool whose
/// upstream changes that layout needs its own validation path, not a new
/// field here: this is a table of names, not a packaging framework.
struct ToolSpec {
    /// Formula file name, binary name, archive prefix, and config key.
    name: &'static str,
    /// GitHub `owner/repo` that publishes the releases.
    repository: &'static str,
    /// Ruby class name Homebrew derives from the formula file name.
    class_name: &'static str,
    description: &'static str,
    /// Ruby expression for the formula's `license` line.
    license: &'static str,
    /// Body of the formula's `test do` block, indented for the template, that
    /// demonstrates useful behavior rather than merely reporting a version.
    test_body: &'static str,
}

const TREEWARD: ToolSpec = ToolSpec {
    name: "treeward",
    repository: "scode/treeward",
    class_name: "Treeward",
    description: "A command line tool for checksumming and verifying trees of files",
    license: r#"any_of: ["MIT", "Apache-2.0"]"#,
    test_body: r##"    (testpath/"content").write "original"
    system bin/"treeward", "init"
    system bin/"treeward", "verify"
    File.write(testpath/"content", "changed")
    assert_match "Verification failed", shell_output("#{bin}/treeward verify 2>&1", 1)"##,
};

// The passphrase goes through `--passphrase-stdin` because the default is an
// interactive terminal prompt, which `brew test` cannot answer. A round trip
// proves encryption works; the wrong-passphrase decrypt proves the check is
// real rather than a pass-through.
const SALTYBOX: ToolSpec = ToolSpec {
    name: "saltybox",
    repository: "scode/saltybox",
    class_name: "Saltybox",
    description: "Passphrase-based file encryption tool",
    license: r#"any_of: ["Apache-2.0", "MIT"]"#,
    test_body: r##"    (testpath/"secret.txt").write "top secret"
    pipe_output("#{bin}/saltybox --passphrase-stdin encrypt -i secret.txt -o secret.saltybox", "correct horse", 0)
    pipe_output("#{bin}/saltybox --passphrase-stdin decrypt -i secret.saltybox -o roundtrip.txt", "correct horse", 0)
    assert_equal "top secret", (testpath/"roundtrip.txt").read
    wrong = pipe_output("#{bin}/saltybox --passphrase-stdin decrypt -i secret.saltybox -o wrong.txt 2>&1", "wrong", 1)
    assert_match "failed to decrypt", wrong
    refute_path_exists testpath/"wrong.txt""##,
};

const TOOLS: [&ToolSpec; 2] = [&SALTYBOX, &TREEWARD];

/// Resolve a name from the CLI or configuration to its registered contract.
fn tool_spec(name: &str) -> Result<&'static ToolSpec> {
    TOOLS
        .into_iter()
        .find(|spec| spec.name == name)
        .ok_or_else(|| anyhow!("unsupported tool: {name}"))
}

/// Update or render the small set of formulas that this tap explicitly opts in.
#[derive(Parser)]
#[command(name = "cargo xtask", version, disable_help_subcommand = true)]
struct Cli {
    /// Configuration path, relative to the invocation directory when omitted.
    #[arg(long, global = true, default_value = "pull.toml")]
    config: PathBuf,
    /// Formula directory, relative to the invocation directory when explicit.
    #[arg(long, global = true)]
    output_dir: Option<PathBuf>,
    /// Include diagnostic details on stderr.
    #[arg(long, global = true)]
    verbose: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Select an explicit release and calculate all recorded archive hashes.
    Update(UpdateArgs),
    /// Rebuild formulas from recorded tags and hashes.
    Regenerate(RegenerateArgs),
}

#[derive(Args)]
struct UpdateArgs {
    tool: String,
    #[arg(long)]
    tag: String,
    /// Validate and report changes without writing files.
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args)]
struct RegenerateArgs {
    /// Fail when rendered formulas differ, without writing files.
    #[arg(long)]
    check: bool,
}

/// The on-disk source of truth for all opted-in tools.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Config {
    schema_version: u32,
    tools: BTreeMap<String, Tool>,
}

/// One selected release, with digests pinning otherwise mutable URLs.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Tool {
    tag: String,
    sha256: BTreeMap<String, String>,
}

/// Tests substitute deterministic archives here; production is the only network user.
trait Fetcher {
    fn get(&self, url: &str) -> Result<Vec<u8>>;
}

/// Blocking HTTPS fetcher with narrow redirect, timeout, and size policies.
struct HttpFetcher {
    client: Client,
}

impl HttpFetcher {
    fn new() -> Result<Self> {
        let redirect = Policy::custom(|attempt| {
            if attempt.previous().len() > 5 || attempt.url().scheme() != "https" {
                attempt.error("only up to five HTTPS redirects are permitted")
            } else {
                attempt.follow()
            }
        });
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(15))
            .timeout(Duration::from_secs(120))
            .redirect(redirect)
            .build()
            .context("build HTTPS client")?;
        Ok(Self { client })
    }
}

impl Fetcher for HttpFetcher {
    fn get(&self, url: &str) -> Result<Vec<u8>> {
        let parsed = Url::parse(url).context("construct release URL")?;
        if parsed.scheme() != "https" || parsed.host_str() != Some("github.com") {
            bail!("refusing non-GitHub HTTPS release URL: {url}");
        }
        let response = self
            .client
            .get(parsed)
            .send()
            .context("download release asset")?;
        if !response.status().is_success() {
            bail!("release asset returned HTTP {}", response.status());
        }
        if response
            .content_length()
            .is_some_and(|length| length > MAX_COMPRESSED)
        {
            bail!("compressed asset exceeds {MAX_COMPRESSED} bytes");
        }
        let mut bytes = Vec::new();
        response
            .take(MAX_COMPRESSED + 1)
            .read_to_end(&mut bytes)
            .context("read release asset")?;
        if bytes.len() as u64 > MAX_COMPRESSED {
            bail!("compressed asset exceeds {MAX_COMPRESSED} bytes");
        }
        Ok(bytes)
    }
}

/// Filesystem operations that tests can fail at a publication boundary.
trait FileOps {
    fn before_stage(&self, _path: &Path) -> io::Result<()> {
        Ok(())
    }

    /// Keep partial-write failures testable without changing process or filesystem policy.
    fn write_stage(&self, file: &mut fs::File, bytes: &[u8]) -> io::Result<()> {
        file.write_all(bytes)
    }

    fn rename(&self, from: &Path, to: &Path) -> io::Result<()> {
        fs::rename(from, to)
    }

    fn remove_file(&self, path: &Path) -> io::Result<()> {
        fs::remove_file(path)
    }
}

/// Production filesystem behavior; all test failures are injected outside it.
struct RealFileOps;
impl FileOps for RealFileOps {}

/// A complete replacement and the original text used for comparison and rollback.
struct Output {
    path: PathBuf,
    text: String,
    original: Option<String>,
}

/// An owned create-new temporary file that is explicitly cleaned on errors.
struct Stage {
    path: PathBuf,
}

fn main() {
    let cli = Cli::parse();
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(if cli.verbose {
            tracing::Level::DEBUG
        } else {
            tracing::Level::INFO
        })
        .without_time()
        .with_writer(std::io::stderr)
        .finish();
    tracing::subscriber::set_global_default(subscriber).expect("install tracing subscriber");
    if let Err(error) = HttpFetcher::new().and_then(|fetcher| run(cli, &fetcher)) {
        eprintln!("error: {error:#}");
        std::process::exit(1);
    }
}

/// Resolve invocation-relative paths, then execute without changing process state.
fn run(cli: Cli, fetcher: &dyn Fetcher) -> Result<()> {
    let cwd = std::env::current_dir().context("read invocation directory")?;
    run_from(cli, &cwd, fetcher, &RealFileOps)
}

/// Execute against an explicit base path so tests never mutate the process cwd.
fn run_from(cli: Cli, cwd: &Path, fetcher: &dyn Fetcher, files: &dyn FileOps) -> Result<()> {
    // Inspect the supplied spelling first: normalizing `link/..` would hide the
    // symlink and silently choose a different destination from filesystem traversal.
    validate_components(&cwd.join(&cli.config), "configuration")?;
    let config_path = lexical_absolute(cwd, &cli.config);
    validate_config_path(&config_path)?;
    let original = fs::read_to_string(&config_path)
        .with_context(|| format!("read configuration {}", config_path.display()))?;
    let mut config: Config = toml::from_str(&original).context("parse configuration")?;
    validate_config(&config)?;
    let output_dir = cli
        .output_dir
        .as_ref()
        .map(|path| cwd.join(path))
        .unwrap_or_else(|| config_path.parent().unwrap_or(cwd).join("Formula"));

    match cli.command {
        Command::Update(args) => {
            validate_tool_name(&args.tool)?;
            validate_tag(&args.tag)?;
            update(
                &mut config,
                &config_path,
                &output_dir,
                &args.tool,
                &args.tag,
                args.dry_run,
                fetcher,
                files,
            )
        }
        Command::Regenerate(args) => regenerate(
            &config,
            &config_path,
            &output_dir,
            args.check,
            fetcher,
            files,
        ),
    }
}

/// Normalize lexical aliases without following links or requiring a path to exist.
fn lexical_absolute(cwd: &Path, path: &Path) -> PathBuf {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        cwd.join(path)
    };
    let mut normalized = PathBuf::new();
    for component in joined.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    normalized
}

/// Reject link traversal and metadata errors for every existing path component.
fn validate_components(path: &Path, label: &str) -> Result<()> {
    let mut missing = false;
    let components: Vec<_> = path.ancestors().collect();
    for component in components.into_iter().rev() {
        if component.as_os_str().is_empty() {
            continue;
        }
        match fs::symlink_metadata(component) {
            Ok(metadata) => {
                if missing {
                    bail!(
                        "path exists beneath a missing {label} ancestor: {}",
                        component.display()
                    );
                }
                if metadata.file_type().is_symlink() {
                    bail!("refusing symlink in {label} path: {}", component.display());
                }
                if component != path && !metadata.is_dir() {
                    bail!("non-directory in {label} path: {}", component.display());
                }
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => missing = true,
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("inspect {label} path {}", component.display()));
            }
        }
    }
    Ok(())
}

/// Require the configuration to be an existing regular file reached without links.
fn validate_config_path(path: &Path) -> Result<()> {
    validate_components(path, "configuration")?;
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("inspect configuration {}", path.display()))?;
    if !metadata.is_file() {
        bail!("configuration is not a regular file: {}", path.display());
    }
    Ok(())
}

/// Read an optional UTF-8 destination while distinguishing absence from failures.
fn read_optional_text(path: &Path, label: &str) -> Result<Option<String>> {
    match fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error).with_context(|| format!("read {label} {}", path.display())),
    }
}

/// Enforce the narrow schema before a command uses recorded release values.
fn validate_config(config: &Config) -> Result<()> {
    if config.schema_version != 1 {
        bail!("unsupported schema_version: {}", config.schema_version);
    }
    for (name, tool) in &config.tools {
        validate_tool_name(name).with_context(|| format!("configured tool {name}"))?;
        validate_tag(&tool.tag).with_context(|| format!("configured tool {name}"))?;
        let found: BTreeSet<_> = tool.sha256.keys().map(String::as_str).collect();
        let expected: BTreeSet<_> = TARGETS.into_iter().collect();
        if found != expected {
            bail!("{name} must record exactly the four supported target hashes");
        }
        for (target, hash) in &tool.sha256 {
            if hash.len() != 64
                || !hash
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
            {
                bail!("{name} has an invalid lowercase SHA-256 digest for {target}");
            }
        }
    }
    Ok(())
}

/// Limit both configuration keys and CLI selection to registered implementations.
fn validate_tool_name(name: &str) -> Result<()> {
    tool_spec(name).map(|_| ())
}

/// Accept SemVer only after excluding characters unsafe in URLs and Ruby literals.
fn validate_tag(tag: &str) -> Result<()> {
    if !tag.starts_with('v')
        || !tag
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'+'))
    {
        bail!("tag must be a safe v-prefixed SemVer value");
    }
    Version::parse(&tag[1..]).context("tag must be valid SemVer")?;
    Ok(())
}

/// Select a release only after destination and archive validation succeeds.
#[allow(clippy::too_many_arguments)]
fn update(
    config: &mut Config,
    config_path: &Path,
    output_dir: &Path,
    tool_name: &str,
    tag: &str,
    dry_run: bool,
    fetcher: &dyn Fetcher,
    files: &dyn FileOps,
) -> Result<()> {
    let spec = tool_spec(tool_name)?;
    let (formula_path, formula_original) =
        prepare_output_set(config_path, output_dir, [tool_name])?
            .pop()
            .expect("one requested tool");
    let hashes = acquire(spec, tag, fetcher)?;
    if let Some(previous) = config.tools.get(tool_name)
        && previous.tag == tag
        && previous.sha256 != hashes
    {
        bail!("same-tag update found changed archive bytes for {tag}");
    }
    config.tools.insert(
        tool_name.to_owned(),
        Tool {
            tag: tag.to_owned(),
            sha256: hashes,
        },
    );
    let config_text = toml::to_string_pretty(config).context("serialize configuration")?;
    let formula_text = render(spec, config.tools.get(tool_name).expect("inserted tool"))?;
    let outputs = vec![
        output(config_path, config_text, "configuration")?,
        Output {
            path: formula_path,
            text: formula_text,
            original: formula_original,
        },
    ];
    if dry_run {
        report_changes(&outputs);
        return Ok(());
    }
    publish_outputs(outputs, files)
}

/// Verify recorded bytes before checking or publishing every generated formula.
fn regenerate(
    config: &Config,
    config_path: &Path,
    output_dir: &Path,
    check: bool,
    fetcher: &dyn Fetcher,
    files: &dyn FileOps,
) -> Result<()> {
    if config.tools.is_empty() {
        return Ok(());
    }
    let paths = prepare_output_set(
        config_path,
        output_dir,
        config.tools.keys().map(String::as_str),
    )?;
    let mut outputs = Vec::with_capacity(paths.len());
    for ((name, tool), (path, original)) in config.tools.iter().zip(paths) {
        let spec = tool_spec(name)?;
        let actual = acquire(spec, &tool.tag, fetcher)?;
        if actual != tool.sha256 {
            bail!("recorded hashes do not match downloaded {name} assets");
        }
        outputs.push(Output {
            path,
            text: render(spec, tool)?,
            original,
        });
    }
    if check {
        let drift: Vec<_> = outputs
            .iter()
            .filter(|output| output.original.as_deref() != Some(output.text.as_str()))
            .collect();
        for output in &drift {
            info!(path = %output.path.display(), "formula drift detected");
        }
        if !drift.is_empty() {
            bail!("generated formulas differ from recorded configuration");
        }
        return Ok(());
    }
    publish_outputs(outputs, files)
}

/// Validate all formula paths and collisions before the first fetch.
fn prepare_output_set<'a>(
    config_path: &Path,
    output_dir: &Path,
    tools: impl IntoIterator<Item = &'a str>,
) -> Result<Vec<(PathBuf, Option<String>)>> {
    validate_components(output_dir, "output directory")?;
    let normalized_output = lexical_absolute(Path::new("/"), output_dir);
    let output_dir = normalized_output.as_path();
    match fs::symlink_metadata(output_dir) {
        Ok(metadata) if !metadata.is_dir() => {
            bail!("output path is not a directory: {}", output_dir.display());
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error)
                .with_context(|| format!("inspect output directory {}", output_dir.display()));
        }
    }
    let mut seen = BTreeSet::new();
    let normalized_config = lexical_absolute(Path::new("/"), config_path);
    let mut paths = Vec::new();
    for tool in tools {
        let path = lexical_absolute(Path::new("/"), &output_dir.join(format!("{tool}.rb")));
        validate_components(&path, "formula destination")?;
        match fs::symlink_metadata(&path) {
            Ok(metadata) if !metadata.is_file() => {
                bail!(
                    "formula destination is not a regular file: {}",
                    path.display()
                );
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("inspect formula destination {}", path.display()));
            }
        }
        if path == normalized_config {
            bail!(
                "formula destination collides with configuration: {}",
                path.display()
            );
        }
        if !seen.insert(path.clone()) {
            bail!("formula destinations collide: {}", path.display());
        }
        let original = read_optional_text(&path, "formula")?;
        paths.push((path, original));
    }
    Ok(paths)
}

/// Capture destination text once so comparison, backup, and publication agree.
fn output(path: &Path, text: String, label: &str) -> Result<Output> {
    Ok(Output {
        path: path.to_path_buf(),
        original: read_optional_text(path, label)?,
        text,
    })
}

/// Download and validate the complete platform set so partial releases never publish.
fn acquire(spec: &ToolSpec, tag: &str, fetcher: &dyn Fetcher) -> Result<BTreeMap<String, String>> {
    let name = spec.name;
    let mut hashes = BTreeMap::new();
    for target in TARGETS {
        let url = release_url(spec, tag, target);
        debug!(%url, %tag, %target, "downloading expected asset");
        let bytes = fetcher
            .get(&url)
            .with_context(|| format!("download {name} {tag} target {target} from {url}"))?;
        validate_archive(spec, &bytes, target)
            .with_context(|| format!("validate {name} {tag} target {target} archive from {url}"))?;
        hashes.insert(target.to_owned(), hex_digest(&bytes));
    }
    Ok(hashes)
}

/// Construct the only upstream location accepted for a tool's release artifact.
fn release_url(spec: &ToolSpec, tag: &str, target: &str) -> String {
    format!(
        "https://github.com/{}/releases/download/{tag}/{}-{target}.tar.xz",
        spec.repository, spec.name
    )
}

/// Treeward-specific spelling retained for the test module's fixtures.
#[cfg(test)]
fn treeward_url(tag: &str, target: &str) -> String {
    release_url(&TREEWARD, tag, target)
}

/// Render compressed-byte identity in the schema's canonical lowercase form.
fn hex_digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

/// Resource bounds cover the entire compressed and expanded containers.
#[derive(Clone, Copy)]
struct ArchiveLimits {
    compressed: u64,
    expanded: u64,
    decoder_memory: u64,
    entries: usize,
}

const ARCHIVE_LIMITS: ArchiveLimits = ArchiveLimits {
    compressed: MAX_COMPRESSED,
    expanded: MAX_EXPANDED,
    decoder_memory: MAX_EXPANDED,
    entries: MAX_ENTRIES,
};

/// Validate the exact release layout and the complete xz and tar containers.
fn validate_archive(spec: &ToolSpec, bytes: &[u8], target: &str) -> Result<()> {
    validate_archive_with_limits(spec, bytes, target, ARCHIVE_LIMITS)
}

/// Treeward-specific spelling retained for the test module.
#[cfg(test)]
fn validate_treeward_archive(bytes: &[u8], target: &str) -> Result<()> {
    validate_archive(&TREEWARD, bytes, target)
}

/// Treeward-specific spelling retained for the test module.
#[cfg(test)]
fn validate_treeward_archive_with_limits(
    bytes: &[u8],
    target: &str,
    limits: ArchiveLimits,
) -> Result<()> {
    validate_archive_with_limits(&TREEWARD, bytes, target, limits)
}

/// Keep test bounds small while production uses the documented resource limits.
fn validate_archive_with_limits(
    spec: &ToolSpec,
    bytes: &[u8],
    target: &str,
    limits: ArchiveLimits,
) -> Result<()> {
    if bytes.len() as u64 > limits.compressed {
        bail!("compressed asset exceeds {} bytes", limits.compressed);
    }
    let stream = Stream::new_stream_decoder(limits.decoder_memory, 0)
        .context("set xz decoder memory limit")?;
    let cursor = Cursor::new(bytes);
    let mut decoder = xz2::bufread::XzDecoder::new_stream(cursor, stream);
    let mut expanded = Vec::new();
    let mut buffer = [0_u8; 16 * 1024];
    loop {
        let count = decoder.read(&mut buffer).context("decompress xz archive")?;
        if count == 0 {
            break;
        }
        if expanded.len() as u64 + count as u64 > limits.expanded {
            bail!(
                "archive exceeds decompressed size limit of {} bytes",
                limits.expanded
            );
        }
        expanded.extend_from_slice(&buffer[..count]);
    }
    let compressed_position = decoder.into_inner().position();
    if compressed_position != bytes.len() as u64 {
        bail!("compressed asset contains a second xz stream or trailing junk");
    }

    let mut archive = Archive::new(Cursor::new(expanded.as_slice()));
    let root = format!("{}-{target}", spec.name);
    let binary = format!("{root}/{}", spec.name);
    let expected: BTreeSet<String> = [
        root.clone(),
        format!("{root}/README.md"),
        format!("{root}/CHANGELOG.md"),
        format!("{root}/LICENSE"),
        binary.clone(),
    ]
    .into_iter()
    .collect();
    let mut found = BTreeSet::new();
    let mut binary_executable = false;
    // Cooked iteration hides GNU/PAX extension headers. Every physical entry must
    // pass the fixed release contract, including headers that alter later entries.
    for (index, item) in archive
        .entries()
        .context("read tar entries")?
        .raw(true)
        .enumerate()
    {
        if index >= limits.entries {
            bail!("archive contains more than {} entries", limits.entries);
        }
        let mut entry = item.context("read tar entry")?;
        let path = entry.path().context("read archive path")?;
        if path.is_absolute()
            || path.components().any(|component| {
                matches!(
                    component,
                    Component::ParentDir | Component::RootDir | Component::Prefix(_)
                )
            })
        {
            bail!("archive contains unsafe path: {}", path.display());
        }
        let raw_text = path
            .to_str()
            .ok_or_else(|| anyhow!("archive path is not UTF-8"))?
            .to_owned();
        // Tar directory headers commonly retain a slash that denotes the same path.
        let text = raw_text.strip_suffix('/').unwrap_or(&raw_text).to_owned();
        if !expected.contains(&text) || !found.insert(text.clone()) {
            bail!("unexpected or duplicate archive path: {text}");
        }
        let kind = entry.header().entry_type();
        if text == root {
            if kind != EntryType::Directory {
                bail!("archive root is not a directory");
            }
        } else if kind != EntryType::Regular {
            bail!("archive contains a non-regular file: {text}");
        } else if text == binary {
            binary_executable = entry.header().mode().context("read executable mode")? & 0o111 != 0;
        }
        io::copy(&mut entry, &mut io::sink()).context("consume archive entry")?;
    }
    let tar_position = archive.into_inner().position() as usize;
    let trailing = expanded
        .get(tar_position..)
        .ok_or_else(|| anyhow!("tar reader advanced beyond decompressed archive"))?;
    if trailing.len() < 512 || trailing.iter().any(|byte| *byte != 0) {
        bail!("archive lacks a complete tar end marker or has nonzero trailing data");
    }
    if found != expected || !binary_executable {
        bail!("archive does not contain the expected executable release layout");
    }
    Ok(())
}

/// Treeward-specific spelling retained for the test module.
#[cfg(test)]
fn render_treeward(tool: &Tool) -> Result<String> {
    render(&TREEWARD, tool)
}

/// Compose Ruby from validated local values rather than upstream formula code.
fn render(spec: &ToolSpec, tool: &Tool) -> Result<String> {
    let version = tool
        .tag
        .strip_prefix('v')
        .ok_or_else(|| anyhow!("invalid tag"))?;
    let hash = |target| tool.sha256.get(target).expect("validated target set");
    Ok(format!(
        r##"class {class_name} < Formula
  desc "{description}"
  homepage "https://github.com/{repository}"
  version "{version}"
  license {license}

  on_macos do
    on_arm do
      url "{aa_url}"
      sha256 "{aa_hash}"
    end

    on_intel do
      url "{xa_url}"
      sha256 "{xa_hash}"
    end
  end

  on_linux do
    on_arm do
      url "{al_url}"
      sha256 "{al_hash}"
    end

    on_intel do
      url "{xl_url}"
      sha256 "{xl_hash}"
    end
  end

  def install
    bin.install "{name}"
    doc.install "README.md", "CHANGELOG.md", "LICENSE"
  end

  test do
{test_body}
  end
end
"##,
        class_name = spec.class_name,
        description = spec.description,
        repository = spec.repository,
        license = spec.license,
        name = spec.name,
        test_body = spec.test_body,
        aa_url = release_url(spec, &tool.tag, TARGETS[0]),
        aa_hash = hash(TARGETS[0]),
        al_url = release_url(spec, &tool.tag, TARGETS[1]),
        al_hash = hash(TARGETS[1]),
        xa_url = release_url(spec, &tool.tag, TARGETS[2]),
        xa_hash = hash(TARGETS[2]),
        xl_url = release_url(spec, &tool.tag, TARGETS[3]),
        xl_hash = hash(TARGETS[3]),
    ))
}

/// Report byte-level dry-run changes without touching their parent paths.
fn report_changes(outputs: &[Output]) {
    for output in outputs {
        if output.original.as_deref() != Some(output.text.as_str()) {
            info!(path = %output.path.display(), "would change");
        }
    }
}

/// Stage every changed output before publishing any and roll back ordinary failures.
fn publish_outputs(outputs: Vec<Output>, files: &dyn FileOps) -> Result<()> {
    let changed: Vec<_> = outputs
        .into_iter()
        .filter(|output| output.original.as_deref() != Some(output.text.as_str()))
        .collect();
    if changed.is_empty() {
        return Ok(());
    }
    let created_dirs = create_missing_parents(&changed)?;
    let result = publish_staged(&changed, files);
    if let Err(error) = result {
        return Err(combine_errors(error, remove_created_dirs(&created_dirs)));
    }
    Ok(())
}

/// Create parent directories only after validation and archive acquisition.
fn create_missing_parents(outputs: &[Output]) -> Result<Vec<PathBuf>> {
    let mut missing = BTreeSet::new();
    for output in outputs {
        let parent = output
            .path
            .parent()
            .ok_or_else(|| anyhow!("destination has no parent"))?;
        let mut current = parent;
        while !current.exists() {
            missing.insert(current.to_path_buf());
            current = current
                .parent()
                .ok_or_else(|| anyhow!("missing path has no existing ancestor"))?;
        }
    }
    let mut planned: Vec<_> = missing.into_iter().collect();
    planned.sort_by_key(|path| path.components().count());
    let mut created = Vec::new();
    for path in planned {
        if let Err(error) =
            fs::create_dir(&path).with_context(|| format!("create {}", path.display()))
        {
            return Err(combine_errors(error, remove_created_dirs(&created)));
        }
        created.push(path.clone());
        if let Err(error) = validate_components(&path, "output directory") {
            return Err(combine_errors(error, remove_created_dirs(&created)));
        }
    }
    Ok(created)
}

/// Remove newly created directories from leaves upward and retain every failure.
fn remove_created_dirs(paths: &[PathBuf]) -> Vec<anyhow::Error> {
    let mut errors = Vec::new();
    for path in paths.iter().rev() {
        match fs::remove_dir(path) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                errors.push(
                    anyhow!(error).context(format!("remove created directory {}", path.display())),
                );
            }
        }
    }
    errors
}

/// Stage replacements and backups before the first destination rename.
fn publish_staged(outputs: &[Output], files: &dyn FileOps) -> Result<()> {
    let mut replacements = Vec::with_capacity(outputs.len());
    let mut backups = Vec::with_capacity(outputs.len());
    for output in outputs {
        match stage_file(
            &output.path,
            output.text.as_bytes(),
            output.original.is_some(),
            files,
        ) {
            Ok(stage) => replacements.push(Some(stage)),
            Err(error) => return cleanup_error(error, replacements, backups, files),
        }
        match &output.original {
            Some(original) => match stage_file(&output.path, original.as_bytes(), true, files) {
                Ok(stage) => backups.push(Some(stage)),
                Err(error) => return cleanup_error(error, replacements, backups, files),
            },
            None => backups.push(None),
        }
    }

    for (index, output) in outputs.iter().enumerate() {
        let stage = replacements[index].take().expect("replacement stage");
        if let Err(error) = files.rename(&stage.path, &output.path) {
            replacements[index] = Some(stage);
            let primary = anyhow!(error).context(format!("publish {}", output.path.display()));
            let rollback = rollback_outputs(outputs, &mut backups, index, files);
            let combined = combine_errors(primary, rollback);
            return cleanup_error(combined, replacements, backups, files);
        }
    }
    cleanup_success(backups, files)
}

/// Prepare complete replacement bytes on the destination filesystem before publication.
///
/// A create-new temporary file avoids shared names and symlink following. Keeping it
/// beside the destination makes the later rename a single-filesystem operation.
fn stage_file(
    path: &Path,
    bytes: &[u8],
    preserve_mode: bool,
    files: &dyn FileOps,
) -> Result<Stage> {
    files
        .before_stage(path)
        .with_context(|| format!("stage {}", path.display()))?;
    let parent = path
        .parent()
        .ok_or_else(|| anyhow!("destination has no parent"))?;
    let temporary = TempBuilder::new()
        .prefix(".pull-")
        .tempfile_in(parent)
        .with_context(|| format!("create stage beside {}", path.display()))?;
    // Take cleanup ownership before writing: tempfile's Drop cannot report an
    // unlink failure after a partial write, permissions error, or failed sync.
    let (mut file, stage_path) = match temporary.keep() {
        Ok(retained) => retained,
        Err(error) => {
            let stage_path = error.file.path().to_owned();
            let primary =
                anyhow!(error.error).context(format!("retain stage {}", stage_path.display()));
            let cleanup = error.file.close().err().map(|error| {
                anyhow!(error).context(format!("remove stage {}", stage_path.display()))
            });
            return Err(combine_errors(primary, cleanup.into_iter().collect()));
        }
    };
    let stage = Stage { path: stage_path };
    let prepared = (|| {
        files
            .write_stage(&mut file, bytes)
            .with_context(|| format!("write stage for {}", path.display()))?;
        set_stage_permissions(&file, path, preserve_mode)?;
        file.sync_all()
            .with_context(|| format!("sync stage for {}", path.display()))
    })();
    drop(file);
    match prepared {
        Ok(()) => Ok(stage),
        Err(error) => Err(combine_errors(
            error,
            cleanup_stages(vec![Some(stage)], files),
        )),
    }
}

#[cfg(unix)]
/// Retain replacement modes and make newly generated formulas ordinary data files.
fn set_stage_permissions(file: &fs::File, destination: &Path, preserve: bool) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    let mode = if preserve {
        fs::metadata(destination)
            .with_context(|| format!("read permissions for {}", destination.display()))?
            .permissions()
            .mode()
    } else {
        0o644
    };
    file.set_permissions(fs::Permissions::from_mode(mode))
        .with_context(|| format!("set permissions for {}", destination.display()))
}

#[cfg(not(unix))]
/// Non-Unix platforms have no numeric mode contract in this tool.
fn set_stage_permissions(_file: &fs::File, _destination: &Path, _preserve: bool) -> Result<()> {
    Ok(())
}

/// Restore every destination published before a later rename failed.
fn rollback_outputs(
    outputs: &[Output],
    backups: &mut [Option<Stage>],
    published: usize,
    files: &dyn FileOps,
) -> Vec<anyhow::Error> {
    let mut errors = Vec::new();
    for index in (0..published).rev() {
        if let Some(stage) = backups[index].take() {
            if let Err(error) = files.rename(&stage.path, &outputs[index].path) {
                errors.push(
                    anyhow!(error).context(format!("roll back {}", outputs[index].path.display())),
                );
                backups[index] = Some(stage);
            }
        } else if let Err(error) = files.remove_file(&outputs[index].path) {
            errors.push(
                anyhow!(error).context(format!("roll back {}", outputs[index].path.display())),
            );
        }
    }
    errors
}

/// Remove obsolete backups after every replacement has reached its destination.
fn cleanup_success(stages: Vec<Option<Stage>>, files: &dyn FileOps) -> Result<()> {
    let errors = cleanup_stages(stages, files);
    if errors.is_empty() {
        Ok(())
    } else {
        Err(combine_errors(
            anyhow!("published outputs but failed to clean staging files"),
            errors,
        ))
    }
}

/// Add temporary-file cleanup failures to the error that triggered cleanup.
fn cleanup_error(
    primary: anyhow::Error,
    replacements: Vec<Option<Stage>>,
    backups: Vec<Option<Stage>>,
    files: &dyn FileOps,
) -> Result<()> {
    let mut errors = cleanup_stages(replacements, files);
    errors.extend(cleanup_stages(backups, files));
    Err(combine_errors(primary, errors))
}

/// Attempt every owned cleanup so one failure does not strand unrelated stages.
fn cleanup_stages(stages: Vec<Option<Stage>>, files: &dyn FileOps) -> Vec<anyhow::Error> {
    let mut errors = Vec::new();
    for stage in stages.into_iter().flatten() {
        match files.remove_file(&stage.path) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                errors
                    .push(anyhow!(error).context(format!("remove stage {}", stage.path.display())));
            }
        }
    }
    errors
}

/// Preserve the primary failure while making rollback and cleanup failures visible.
fn combine_errors(primary: anyhow::Error, secondary: Vec<anyhow::Error>) -> anyhow::Error {
    if secondary.is_empty() {
        primary
    } else {
        let details = secondary
            .iter()
            .map(|error| format!("{error:#}"))
            .collect::<Vec<_>>()
            .join("; ");
        primary.context(format!(
            "additional rollback or cleanup failures: {details}"
        ))
    }
}

#[cfg(test)]
mod tests;
