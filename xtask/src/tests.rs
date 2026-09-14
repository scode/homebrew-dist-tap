use std::{
    cell::Cell,
    collections::{BTreeMap, BTreeSet},
    fs,
    io::{self, Cursor, Read},
    path::{Path, PathBuf},
};

use anyhow::{Result, anyhow};
use tar::{EntryType, Header};
use tempfile::tempdir;
use xz2::read::XzEncoder;

use super::*;

/// Fixture archives exercise the real tar and xz parsers without mutable network data.
struct Fixtures {
    responses: BTreeMap<String, Vec<u8>>,
    calls: Cell<usize>,
}

impl Fixtures {
    fn for_tag(tag: &str) -> Self {
        Self::for_tools(&[(&TREEWARD, tag)])
    }

    /// Serve one release per listed tool so multi-tool regeneration can be exercised.
    fn for_tools(releases: &[(&ToolSpec, &str)]) -> Self {
        let responses = releases
            .iter()
            .flat_map(|(spec, tag)| {
                TARGETS.into_iter().map(move |target| {
                    (
                        release_url(spec, tag, target),
                        archive_named(spec.name, target, |_| {}),
                    )
                })
            })
            .collect();
        Self {
            responses,
            calls: Cell::new(0),
        }
    }
}

impl Fetcher for Fixtures {
    fn get(&self, url: &str) -> Result<Vec<u8>> {
        self.calls.set(self.calls.get() + 1);
        self.responses
            .get(url)
            .cloned()
            .ok_or_else(|| anyhow!("missing fixture for {url}"))
    }
}

/// Failure injection is limited to staging and rename boundaries used by publication.
struct FailingFiles {
    stages: Cell<usize>,
    renames: Cell<usize>,
    fail_stage: Option<usize>,
    fail_renames: BTreeSet<usize>,
}

impl FailingFiles {
    fn stage(number: usize) -> Self {
        Self {
            stages: Cell::new(0),
            renames: Cell::new(0),
            fail_stage: Some(number),
            fail_renames: BTreeSet::new(),
        }
    }

    fn renames(numbers: impl IntoIterator<Item = usize>) -> Self {
        Self {
            stages: Cell::new(0),
            renames: Cell::new(0),
            fail_stage: None,
            fail_renames: numbers.into_iter().collect(),
        }
    }
}

impl FileOps for FailingFiles {
    fn before_stage(&self, _path: &Path) -> io::Result<()> {
        let number = self.stages.get() + 1;
        self.stages.set(number);
        if self.fail_stage == Some(number) {
            Err(io::Error::other("injected staging failure"))
        } else {
            Ok(())
        }
    }

    fn rename(&self, from: &Path, to: &Path) -> io::Result<()> {
        let number = self.renames.get() + 1;
        self.renames.set(number);
        if self.fail_renames.contains(&number) {
            Err(io::Error::other(format!(
                "injected rename failure {number}"
            )))
        } else {
            fs::rename(from, to)
        }
    }
}

/// Write headers directly so rejection tests can include paths a safe tar builder refuses.
///
/// The normal end marker remains intact; callers can append bytes after it to test
/// content that a reader stopping at tar's first zero block would otherwise miss.
fn raw_tar(entries: &[(&str, EntryType, u32, &[u8])], tail: &[u8]) -> Vec<u8> {
    let mut bytes = Vec::new();
    for (path, kind, mode, content) in entries {
        let mut header = Header::new_gnu();
        header.set_entry_type(*kind);
        header.set_mode(*mode);
        header.set_size(content.len() as u64);
        header.set_uid(0);
        header.set_gid(0);
        header.set_mtime(0);
        let name = path.as_bytes();
        header.as_mut_bytes()[..name.len()].copy_from_slice(name);
        header.set_cksum();
        bytes.extend_from_slice(header.as_bytes());
        bytes.extend_from_slice(content);
        bytes.resize(bytes.len().div_ceil(512) * 512, 0);
    }
    bytes.extend_from_slice(&[0; 1024]);
    bytes.extend_from_slice(tail);
    bytes
}

/// Encode raw tar bytes with the same container parsed in production.
fn compress(bytes: &[u8]) -> Vec<u8> {
    let mut encoder = XzEncoder::new(Cursor::new(bytes), 1);
    let mut compressed = Vec::new();
    encoder.read_to_end(&mut compressed).unwrap();
    compressed
}

/// Treeward-named archive; most contract tests use it because the layout is shared.
fn archive_with(
    target: &str,
    changes: impl FnOnce(&mut Vec<(String, EntryType, u32, Vec<u8>)>),
) -> Vec<u8> {
    archive_named("treeward", target, changes)
}

/// Build the valid five-entry contract for a tool, then let one test mutate its attack surface.
fn archive_named(
    name: &str,
    target: &str,
    changes: impl FnOnce(&mut Vec<(String, EntryType, u32, Vec<u8>)>),
) -> Vec<u8> {
    let root = format!("{name}-{target}");
    let mut entries = vec![
        (root.clone(), EntryType::Directory, 0o755, Vec::new()),
        (
            format!("{root}/README.md"),
            EntryType::Regular,
            0o644,
            b"readme".to_vec(),
        ),
        (
            format!("{root}/CHANGELOG.md"),
            EntryType::Regular,
            0o644,
            b"changes".to_vec(),
        ),
        (
            format!("{root}/LICENSE"),
            EntryType::Regular,
            0o644,
            b"license".to_vec(),
        ),
        (
            format!("{root}/{name}"),
            EntryType::Regular,
            0o755,
            b"binary".to_vec(),
        ),
    ];
    changes(&mut entries);
    let borrowed: Vec<_> = entries
        .iter()
        .map(|(path, kind, mode, content)| (path.as_str(), *kind, *mode, content.as_slice()))
        .collect();
    compress(&raw_tar(&borrowed, &[]))
}

/// Produce a complete target-specific release archive for fetch fixtures.
fn valid_archive(target: &str) -> Vec<u8> {
    archive_with(target, |_| {})
}

/// Record hashes from exactly the fixture bytes returned for a selected treeward tag.
fn selected(tag: &str, fixtures: &Fixtures) -> Tool {
    selected_for(&TREEWARD, tag, fixtures)
}

/// Record hashes from exactly the fixture bytes returned for a tool's selected tag.
fn selected_for(spec: &ToolSpec, tag: &str, fixtures: &Fixtures) -> Tool {
    let sha256 = TARGETS
        .into_iter()
        .map(|target| {
            let bytes = fixtures
                .responses
                .get(&release_url(spec, tag, target))
                .unwrap();
            (target.to_owned(), hex_digest(bytes))
        })
        .collect();
    Tool {
        tag: tag.to_owned(),
        sha256,
    }
}

/// Construct either the live empty schema or one opted-in treeward selection.
fn config(tool: Option<Tool>) -> Config {
    config_of(tool.into_iter().map(|tool| ("treeward", tool)))
}

/// Construct a configuration opting in the named tools.
fn config_of(tools: impl IntoIterator<Item = (&'static str, Tool)>) -> Config {
    Config {
        schema_version: 1,
        tools: tools
            .into_iter()
            .map(|(name, tool)| (name.to_owned(), tool))
            .collect(),
    }
}

/// Serialize fixture configuration through the same TOML implementation as production.
fn write_config(path: &Path, config: &Config) {
    fs::write(path, toml::to_string_pretty(config).unwrap()).unwrap();
}

/// Build treeward update arguments directly so tests can inject cwd without process mutation.
fn update_cli(config: &Path, output: &Path, tag: &str, dry_run: bool) -> Cli {
    update_cli_for("treeward", config, output, tag, dry_run)
}

/// Build update arguments for any tool name, including unregistered ones.
fn update_cli_for(tool: &str, config: &Path, output: &Path, tag: &str, dry_run: bool) -> Cli {
    Cli {
        config: config.to_path_buf(),
        output_dir: Some(output.to_path_buf()),
        verbose: false,
        command: Command::Update(UpdateArgs {
            tool: tool.to_owned(),
            tag: tag.to_owned(),
            dry_run,
        }),
    }
}

/// Build regeneration arguments directly so tests avoid environment and cwd changes.
fn regenerate_cli(config: &Path, output: &Path, check: bool) -> Cli {
    Cli {
        config: config.to_path_buf(),
        output_dir: Some(output.to_path_buf()),
        verbose: false,
        command: Command::Regenerate(RegenerateArgs { check }),
    }
}

/// Find leaked owned stages recursively after injected failures and cleanup.
fn staging_files(root: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    fn visit(path: &Path, found: &mut Vec<PathBuf>) {
        let Ok(entries) = fs::read_dir(path) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                visit(&path, found);
            } else if path
                .file_name()
                .is_some_and(|name| name.to_string_lossy().starts_with(".pull-"))
            {
                found.push(path);
            }
        }
    }
    visit(root, &mut found);
    found
}

#[test]
/// A first update must publish matching config and formula from four validated archives.
fn successful_update_writes_exact_outputs() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    write_config(&config_path, &config(None));
    let fixtures = Fixtures::for_tag("v1.2.3");

    run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    let expected = config(Some(selected("v1.2.3", &fixtures)));
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        toml::to_string_pretty(&expected).unwrap()
    );
    assert_eq!(
        fs::read_to_string(output.join("treeward.rb")).unwrap(),
        render_treeward(expected.tools.get("treeward").unwrap()).unwrap()
    );
    assert_eq!(fixtures.calls.get(), 4);
}

#[test]
/// A current selection still verifies bytes but must not replace either file.
#[cfg(unix)]
fn same_tag_noop_preserves_file_identity() {
    use std::os::unix::fs::MetadataExt;

    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    let fixtures = Fixtures::for_tag("v1.2.3");
    let selected = selected("v1.2.3", &fixtures);
    write_config(&config_path, &config(Some(selected.clone())));
    fs::write(
        output.join("treeward.rb"),
        render_treeward(&selected).unwrap(),
    )
    .unwrap();
    let before = (
        fs::metadata(&config_path).unwrap().ino(),
        fs::metadata(&config_path).unwrap().modified().unwrap(),
        fs::metadata(output.join("treeward.rb")).unwrap().ino(),
        fs::metadata(output.join("treeward.rb"))
            .unwrap()
            .modified()
            .unwrap(),
    );

    run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(
        before,
        (
            fs::metadata(&config_path).unwrap().ino(),
            fs::metadata(&config_path).unwrap().modified().unwrap(),
            fs::metadata(output.join("treeward.rb")).unwrap().ino(),
            fs::metadata(output.join("treeward.rb"))
                .unwrap()
                .modified()
                .unwrap()
        )
    );
    assert_eq!(fixtures.calls.get(), 4);
}

#[test]
/// Mutable bytes under one tag are an integrity failure and preserve both outputs.
fn same_tag_changed_bytes_preserves_outputs() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    let original = Fixtures::for_tag("v1.2.3");
    let selected = selected("v1.2.3", &original);
    write_config(&config_path, &config(Some(selected.clone())));
    let formula_path = output.join("treeward.rb");
    fs::write(&formula_path, render_treeward(&selected).unwrap()).unwrap();
    let before = (
        fs::read(&config_path).unwrap(),
        fs::read(&formula_path).unwrap(),
    );
    let changed = Fixtures::for_tag("v1.2.3");
    changed
        .responses
        .get(&treeward_url("v1.2.3", TARGETS[0]))
        .unwrap();
    let mut responses = changed.responses;
    responses.insert(
        treeward_url("v1.2.3", TARGETS[0]),
        archive_with(TARGETS[0], |entries| entries[1].3.push(b'x')),
    );
    let changed = Fixtures {
        responses,
        calls: Cell::new(0),
    };

    assert!(
        run_from(
            update_cli(&config_path, &output, "v1.2.3", false),
            directory.path(),
            &changed,
            &RealFileOps
        )
        .is_err()
    );
    assert_eq!(
        before,
        (
            fs::read(&config_path).unwrap(),
            fs::read(&formula_path).unwrap()
        )
    );
}

#[test]
/// A different explicit tag replaces the selected release only after all assets pass.
fn different_tag_updates_both_outputs() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    let old = Fixtures::for_tag("v1.0.0");
    write_config(&config_path, &config(Some(selected("v1.0.0", &old))));
    let new = Fixtures::for_tag("v1.1.0");

    run_from(
        update_cli(&config_path, &output, "v1.1.0", false),
        directory.path(),
        &new,
        &RealFileOps,
    )
    .unwrap();

    let parsed: Config = toml::from_str(&fs::read_to_string(&config_path).unwrap()).unwrap();
    assert_eq!(parsed.tools["treeward"].tag, "v1.1.0");
    assert!(
        fs::read_to_string(output.join("treeward.rb"))
            .unwrap()
            .contains("version \"1.1.0\"")
    );
}

#[test]
/// Incomplete downloads and malformed archives fail before either destination changes.
fn acquisition_failures_preserve_outputs() {
    for malformed in [false, true] {
        let directory = tempdir().unwrap();
        let config_path = directory.path().join("pull.toml");
        let output = directory.path().join("Formula");
        fs::create_dir(&output).unwrap();
        write_config(&config_path, &config(None));
        let formula_path = output.join("treeward.rb");
        fs::write(&formula_path, "unrelated").unwrap();
        let mut fixtures = Fixtures::for_tag("v1.2.3");
        if malformed {
            fixtures
                .responses
                .insert(treeward_url("v1.2.3", TARGETS[2]), b"not xz".to_vec());
        } else {
            fixtures
                .responses
                .remove(&treeward_url("v1.2.3", TARGETS[2]));
        }

        let error = run_from(
            update_cli(&config_path, &output, "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps,
        )
        .unwrap_err();
        let message = format!("{error:#}");
        assert!(message.contains(TARGETS[2]));
        assert!(message.contains("v1.2.3"));
        assert!(message.contains("https://github.com/scode/treeward/releases/download/"));
        assert_eq!(
            fs::read_to_string(&config_path).unwrap(),
            "schema_version = 1\n\n[tools]\n"
        );
        assert_eq!(fs::read_to_string(&formula_path).unwrap(), "unrelated");
    }
}

#[test]
/// Dry-run validates archives without creating output paths or changing config.
fn dry_run_changes_nothing_including_directories() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("missing/deep");
    write_config(&config_path, &config(None));
    let before = fs::read(&config_path).unwrap();

    run_from(
        update_cli(&config_path, &output, "v1.2.3", true),
        directory.path(),
        &Fixtures::for_tag("v1.2.3"),
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(fs::read(&config_path).unwrap(), before);
    assert!(!output.exists());
}

#[test]
/// Check reports missing or changed generated text without writing either state.
fn check_detects_drift_and_never_writes() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    let fixtures = Fixtures::for_tag("v1.2.3");
    write_config(&config_path, &config(Some(selected("v1.2.3", &fixtures))));

    assert!(
        run_from(
            regenerate_cli(&config_path, &output, true),
            directory.path(),
            &fixtures,
            &RealFileOps
        )
        .is_err()
    );
    assert!(!output.exists());
    fs::create_dir(&output).unwrap();
    fs::write(output.join("treeward.rb"), "drift").unwrap();
    assert!(
        run_from(
            regenerate_cli(&config_path, &output, true),
            directory.path(),
            &fixtures,
            &RealFileOps
        )
        .is_err()
    );
    assert_eq!(
        fs::read_to_string(output.join("treeward.rb")).unwrap(),
        "drift"
    );
}

#[test]
/// Empty configuration does no fetch or output-path inspection, even in check mode.
fn empty_config_has_no_network_or_output_activity() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("missing");
    write_config(&config_path, &config(None));
    let fixtures = Fixtures {
        responses: BTreeMap::new(),
        calls: Cell::new(0),
    };

    run_from(
        regenerate_cli(&config_path, &output, true),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(fixtures.calls.get(), 0);
    assert!(!output.exists());
}

#[test]
/// Regeneration replaces only its registered formula and preserves neighboring files.
fn regenerate_preserves_unrelated_formula() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    let fixtures = Fixtures::for_tag("v1.2.3");
    write_config(&config_path, &config(Some(selected("v1.2.3", &fixtures))));
    fs::write(output.join("other.rb"), "keep").unwrap();

    run_from(
        regenerate_cli(&config_path, &output, false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(fs::read_to_string(output.join("other.rb")).unwrap(), "keep");
}

#[test]
/// Regeneration followed by check proves recorded bytes and rendered output agree end to end.
fn regenerate_then_check_round_trip() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    let fixtures = Fixtures::for_tag("v1.2.3");
    let selected = selected("v1.2.3", &fixtures);
    write_config(&config_path, &config(Some(selected.clone())));

    run_from(
        regenerate_cli(&config_path, &output, false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();
    run_from(
        regenerate_cli(&config_path, &output, true),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(
        fs::read_to_string(output.join("treeward.rb")).unwrap(),
        render_treeward(&selected).unwrap()
    );
    assert_eq!(fixtures.calls.get(), 8);
}

#[test]
/// Regeneration must reject wrong recorded hashes before creating a formula directory.
fn regenerate_rejects_wrong_recorded_hashes() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    let fixtures = Fixtures::for_tag("v1.2.3");
    let mut selected = selected("v1.2.3", &fixtures);
    selected
        .sha256
        .insert(TARGETS[0].to_owned(), "0".repeat(64));
    write_config(&config_path, &config(Some(selected)));

    assert!(
        run_from(
            regenerate_cli(&config_path, &output, false),
            directory.path(),
            &fixtures,
            &RealFileOps,
        )
        .is_err()
    );
    assert!(!output.exists());
}

#[test]
/// Strict schema and hash validation reject ambiguous or noncanonical configuration.
fn schema_rejects_unknowns_targets_and_hash_spelling() {
    assert!(toml::from_str::<Config>("schema_version=1\nunknown=1\n[tools]").is_err());
    assert!(
        toml::from_str::<Config>(
            "schema_version=1\n[tools.treeward]\ntag='v1.0.0'\nunknown=1\n[tools.treeward.sha256]"
        )
        .is_err()
    );
    assert!(
        toml::from_str::<Config>("schema_version=1\n[tools.nope]\ntag='v1.0.0'\nsha256={}").is_ok()
    );
    let mut invalid = config(Some(Tool {
        tag: "v1.0.0".to_owned(),
        sha256: BTreeMap::new(),
    }));
    assert!(validate_config(&invalid).is_err());
    invalid.tools.get_mut("treeward").unwrap().sha256 = TARGETS
        .into_iter()
        .map(|target| (target.to_owned(), "A".repeat(64)))
        .collect();
    assert!(validate_config(&invalid).is_err());
    let tool = invalid.tools.remove("treeward").unwrap();
    invalid.tools.insert("nope".to_owned(), tool);
    assert!(validate_config(&invalid).is_err());
}

#[test]
/// Tags enter URLs and Ruby literals, so only the stated safe SemVer subset is accepted.
fn tags_reject_path_and_ruby_injection() {
    for tag in ["1.2.3", "v1.2.3/x", "v1.2.3\"", "v1.2", "v1.2.3 rc"] {
        assert!(validate_tag(tag).is_err(), "accepted {tag}");
    }
    assert!(validate_tag("v1.2.3-rc.1+build.4").is_ok());
}

#[test]
#[cfg(unix)]
/// Collision, special-file, and symlink errors must happen before the fetch seam is called.
fn invalid_destinations_fail_before_fetch() {
    use std::os::unix::fs::symlink;
    use std::os::unix::net::UnixListener;

    let directory = tempdir().unwrap();
    let config_path = directory.path().join("treeward.rb");
    write_config(&config_path, &config(None));
    let fixtures = Fixtures::for_tag("v1.2.3");
    let alias = directory.path().join("unused/../treeward.rb");
    assert!(
        run_from(
            update_cli(&alias, directory.path(), "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps
        )
        .is_err()
    );
    assert_eq!(fixtures.calls.get(), 0);

    let config_directory = directory.path().join("config-dir");
    fs::create_dir(&config_directory).unwrap();
    assert!(
        run_from(
            update_cli(&config_directory, directory.path(), "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps,
        )
        .is_err()
    );
    assert_eq!(fixtures.calls.get(), 0);

    let linked = directory.path().join("linked");
    fs::create_dir(directory.path().join("real")).unwrap();
    symlink(directory.path().join("real"), &linked).unwrap();
    assert!(
        run_from(
            update_cli(&config_path, &linked, "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps
        )
        .is_err()
    );
    assert_eq!(fixtures.calls.get(), 0);

    let leaf_dir = directory.path().join("leaf-link");
    fs::create_dir(&leaf_dir).unwrap();
    symlink("missing-target", leaf_dir.join("treeward.rb")).unwrap();
    assert!(
        run_from(
            update_cli(&config_path, &leaf_dir, "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps,
        )
        .is_err()
    );
    assert_eq!(fixtures.calls.get(), 0);

    let socket_dir = directory.path().join("socket-output");
    fs::create_dir(&socket_dir).unwrap();
    let _listener = UnixListener::bind(socket_dir.join("treeward.rb")).unwrap();
    assert!(
        run_from(
            update_cli(&config_path, &socket_dir, "v1.2.3", false),
            directory.path(),
            &fixtures,
            &RealFileOps
        )
        .is_err()
    );
    assert_eq!(fixtures.calls.get(), 0);
}

#[test]
/// Existing non-UTF-8 formula bytes are errors in dry-run and check, never empty drift.
fn invalid_utf8_destination_is_reported_without_fetch_masking() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    let fixtures = Fixtures::for_tag("v1.2.3");
    write_config(&config_path, &config(Some(selected("v1.2.3", &fixtures))));
    fs::write(output.join("treeward.rb"), [0xff]).unwrap();

    let error = run_from(
        regenerate_cli(&config_path, &output, true),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap_err();
    assert!(format!("{error:#}").contains("stream did not contain valid UTF-8"));
    assert_eq!(fixtures.calls.get(), 0);
    assert_eq!(fs::read(output.join("treeward.rb")).unwrap(), [0xff]);
}

/// Parent cancellation must not hide a link and redirect a scratch request into the tap.
#[test]
#[cfg(unix)]
fn symlink_before_parent_component_fails_before_fetch() {
    use std::os::unix::fs::symlink;

    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    write_config(&config_path, &config(None));
    let original = fs::read(&config_path).unwrap();
    let nested = directory.path().join("elsewhere/nested");
    fs::create_dir_all(&nested).unwrap();
    symlink(&nested, directory.path().join("linked")).unwrap();
    let fixtures = Fixtures::for_tag("v1.2.3");
    let output = directory.path().join("Formula");
    for cli in [
        update_cli(
            &directory.path().join("linked/../pull.toml"),
            &output,
            "v1.2.3",
            false,
        ),
        update_cli(
            &config_path,
            &directory.path().join("linked/../Formula"),
            "v1.2.3",
            false,
        ),
    ] {
        let error = run_from(cli, directory.path(), &fixtures, &RealFileOps).unwrap_err();
        assert!(format!("{error:#}").contains("symlink"));
        assert_eq!(fixtures.calls.get(), 0);
        assert_eq!(fs::read(&config_path).unwrap(), original);
        assert!(!output.exists());
        assert!(!directory.path().join("elsewhere/Formula").exists());
    }
}

/// A real partial file must be cleaned explicitly, and a failed unlink must identify it.
#[test]
fn partial_stage_write_reports_cleanup_failure() {
    struct PartialWrite {
        fail_cleanup: bool,
    }
    impl FileOps for PartialWrite {
        fn write_stage(&self, file: &mut fs::File, _bytes: &[u8]) -> io::Result<()> {
            file.write_all(b"partial")?;
            Err(io::Error::other("injected partial write"))
        }
        fn remove_file(&self, path: &Path) -> io::Result<()> {
            if self.fail_cleanup {
                Err(io::Error::other("injected stage cleanup"))
            } else {
                fs::remove_file(path)
            }
        }
    }
    for fail_cleanup in [false, true] {
        let directory = tempdir().unwrap();
        let destination = directory.path().join("treeward.rb");
        let error = stage_file(
            &destination,
            b"replacement",
            false,
            &PartialWrite { fail_cleanup },
        )
        .err()
        .expect("partial writes fail");
        let message = format!("{error:#}");
        assert!(message.contains("injected partial write"));
        assert!(!destination.exists());
        let remaining = staging_files(directory.path());
        if fail_cleanup {
            assert!(message.contains("injected stage cleanup"));
            assert_eq!(remaining.len(), 1);
            assert!(message.contains(&remaining[0].display().to_string()));
            assert_eq!(fs::read(&remaining[0]).unwrap(), b"partial");
        } else {
            assert!(remaining.is_empty());
        }
    }
}

#[test]
/// Formula-stage failure proves both payloads are staged before config publication.
fn staging_failure_preserves_outputs_and_cleans_temps() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("missing/Formula");
    write_config(&config_path, &config(None));
    let before = fs::read(&config_path).unwrap();

    let error = run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &Fixtures::for_tag("v1.2.3"),
        &FailingFiles::stage(3),
    )
    .unwrap_err();
    assert!(format!("{error:#}").contains("injected staging failure"));
    assert_eq!(fs::read(&config_path).unwrap(), before);
    assert!(!output.exists());
    assert!(staging_files(directory.path()).is_empty());
}

#[test]
#[cfg(unix)]
/// Publication preserves existing modes and gives a new formula ordinary 0644 data mode.
fn publication_preserves_and_assigns_modes() {
    use std::os::unix::fs::PermissionsExt;

    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    write_config(&config_path, &config(None));
    fs::set_permissions(&config_path, fs::Permissions::from_mode(0o600)).unwrap();

    run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &Fixtures::for_tag("v1.2.3"),
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(
        fs::metadata(&config_path).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert_eq!(
        fs::metadata(output.join("treeward.rb"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o644
    );
}

#[test]
/// A failed second rename restores config and removes every owned stage.
fn second_publication_failure_rolls_back_and_cleans() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    write_config(&config_path, &config(None));
    let formula = output.join("treeward.rb");
    fs::write(&formula, "old").unwrap();
    let before = fs::read(&config_path).unwrap();

    let error = run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &Fixtures::for_tag("v1.2.3"),
        &FailingFiles::renames([2]),
    )
    .unwrap_err();
    assert!(format!("{error:#}").contains("injected rename failure 2"));
    assert_eq!(fs::read(&config_path).unwrap(), before);
    assert_eq!(fs::read_to_string(&formula).unwrap(), "old");
    assert!(staging_files(directory.path()).is_empty());
}

#[test]
/// Rollback failure remains visible beside the publication failure and leaves no temp file.
fn rollback_error_is_not_swallowed() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    fs::create_dir(&output).unwrap();
    write_config(&config_path, &config(None));
    fs::write(output.join("treeward.rb"), "old").unwrap();

    let error = run_from(
        update_cli(&config_path, &output, "v1.2.3", false),
        directory.path(),
        &Fixtures::for_tag("v1.2.3"),
        &FailingFiles::renames([2, 3]),
    )
    .unwrap_err();
    let message = format!("{error:#}");
    assert!(message.contains("injected rename failure 2"));
    assert!(message.contains("injected rename failure 3"));
    assert!(staging_files(directory.path()).is_empty());
}

#[test]
/// Archive membership is exact: duplicates, traversal, links, extras, omissions, and modes fail.
fn archive_rejects_member_contract_violations() {
    let target = TARGETS[3];
    let cases = [
        archive_with(target, |entries| entries.push(entries[1].clone())),
        archive_with(target, |entries| entries[1].0 = "../README.md".to_owned()),
        archive_with(target, |entries| entries[1].1 = EntryType::Symlink),
        archive_with(target, |entries| {
            entries.push((
                format!("treeward-{target}/extra"),
                EntryType::Regular,
                0o644,
                vec![],
            ))
        }),
        archive_with(target, |entries| {
            entries.remove(1);
        }),
        archive_with(target, |entries| entries[4].2 = 0o644),
    ];
    for archive in cases {
        assert!(validate_treeward_archive(&archive, target).is_err());
    }
}

/// Extension headers cannot bypass the exact path/type contract through cooked tar iteration.
#[test]
fn archive_rejects_hidden_extension_headers() {
    let target = TARGETS[3];
    for (kind, content) in [
        (
            EntryType::GNULongName,
            format!("treeward-{target}/README.md\0").into_bytes(),
        ),
        (EntryType::GNULongLink, b"ignored-link\0".to_vec()),
        (EntryType::XHeader, b"11 mtime=0\n".to_vec()),
    ] {
        let archive = archive_with(target, |entries| {
            entries.insert(1, ("../unexpected".to_owned(), kind, 0o644, content));
        });
        let error = validate_treeward_archive(&archive, target).unwrap_err();
        assert!(format!("{error:#}").contains("unsafe path"), "{error:#}");
    }
}

#[test]
/// Xz termination and bytes after tar's end marker are part of archive approval.
fn archive_rejects_truncation_extra_streams_and_hidden_payload() {
    let target = TARGETS[3];
    let valid = valid_archive(target);
    assert!(validate_treeward_archive(&valid[..valid.len() - 4], target).is_err());
    let mut corrupt = valid.clone();
    *corrupt.last_mut().unwrap() ^= 1;
    assert!(validate_treeward_archive(&corrupt, target).is_err());
    let mut junk = valid.clone();
    junk.extend_from_slice(b"junk");
    assert!(validate_treeward_archive(&junk, target).is_err());
    let mut concatenated = valid.clone();
    concatenated.extend_from_slice(&valid);
    assert!(validate_treeward_archive(&concatenated, target).is_err());

    let root = format!("treeward-{target}");
    let entries = [
        (root.as_str(), EntryType::Directory, 0o755, &b""[..]),
        (
            &format!("{root}/README.md"),
            EntryType::Regular,
            0o644,
            &b"r"[..],
        ),
        (
            &format!("{root}/CHANGELOG.md"),
            EntryType::Regular,
            0o644,
            &b"c"[..],
        ),
        (
            &format!("{root}/LICENSE"),
            EntryType::Regular,
            0o644,
            &b"l"[..],
        ),
        (
            &format!("{root}/treeward"),
            EntryType::Regular,
            0o755,
            &b"b"[..],
        ),
    ];
    let hidden = compress(&raw_tar(&entries, b"hidden"));
    assert!(validate_treeward_archive(&hidden, target).is_err());
}

#[test]
/// Private small limits efficiently cover compressed, expanded, entry, and decoder-memory bounds.
fn archive_resource_limits_are_enforced() {
    let target = TARGETS[3];
    let valid = valid_archive(target);
    assert!(
        validate_treeward_archive_with_limits(
            &valid,
            target,
            ArchiveLimits {
                compressed: valid.len() as u64 - 1,
                ..ARCHIVE_LIMITS
            },
        )
        .is_err()
    );
    assert!(
        validate_treeward_archive_with_limits(
            &valid,
            target,
            ArchiveLimits {
                expanded: 1024,
                ..ARCHIVE_LIMITS
            },
        )
        .is_err()
    );
    assert!(
        validate_treeward_archive_with_limits(
            &valid,
            target,
            ArchiveLimits {
                entries: 4,
                ..ARCHIVE_LIMITS
            },
        )
        .is_err()
    );
    assert!(
        validate_treeward_archive_with_limits(
            &valid,
            target,
            ArchiveLimits {
                decoder_memory: 1,
                ..ARCHIVE_LIMITS
            },
        )
        .is_err()
    );
}

#[test]
/// Saltybox shares treeward's archive layout but must render its own identity and test,
/// and selecting it must never touch treeward's formula.
fn saltybox_update_renders_its_own_formula() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    write_config(&config_path, &config(None));
    let fixtures = Fixtures::for_tools(&[(&SALTYBOX, "v5.0.1")]);

    run_from(
        update_cli_for("saltybox", &config_path, &output, "v5.0.1", false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    let expected = config_of([("saltybox", selected_for(&SALTYBOX, "v5.0.1", &fixtures))]);
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        toml::to_string_pretty(&expected).unwrap()
    );
    let formula = fs::read_to_string(output.join("saltybox.rb")).unwrap();
    assert_eq!(
        formula,
        render(&SALTYBOX, &expected.tools["saltybox"]).unwrap()
    );
    assert!(formula.starts_with("class Saltybox < Formula\n"));
    assert!(formula.contains("https://github.com/scode/saltybox/releases/download/v5.0.1/saltybox-x86_64-apple-darwin.tar.xz"));
    assert!(formula.contains("--passphrase-stdin"));
    assert!(formula.contains(r#"bin.install "saltybox""#));
    assert!(!formula.contains("treeward"));
    assert!(!output.join("treeward.rb").exists());
    assert_eq!(fixtures.calls.get(), 4);
}

#[test]
/// The archive root and binary are named after the tool, so one tool's release must not
/// validate as another's even though the file set is otherwise identical.
fn archive_root_must_name_the_selected_tool() {
    let target = TARGETS[3];
    let treeward = archive_named("treeward", target, |_| {});
    let saltybox = archive_named("saltybox", target, |_| {});
    assert!(validate_archive(&TREEWARD, &treeward, target).is_ok());
    assert!(validate_archive(&SALTYBOX, &saltybox, target).is_ok());
    assert!(validate_archive(&SALTYBOX, &treeward, target).is_err());
    assert!(validate_archive(&TREEWARD, &saltybox, target).is_err());
}

#[test]
/// Regeneration resolves each configured tool to its own contract, downloading every
/// archive of every tool and rendering each formula from its own spec.
fn regenerate_handles_both_tools() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    let fixtures = Fixtures::for_tools(&[(&SALTYBOX, "v5.0.1"), (&TREEWARD, "v1.2.3")]);
    write_config(
        &config_path,
        &config_of([
            ("saltybox", selected_for(&SALTYBOX, "v5.0.1", &fixtures)),
            ("treeward", selected_for(&TREEWARD, "v1.2.3", &fixtures)),
        ]),
    );

    run_from(
        regenerate_cli(&config_path, &output, false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap();

    assert_eq!(fixtures.calls.get(), 8);
    assert!(
        fs::read_to_string(output.join("saltybox.rb"))
            .unwrap()
            .starts_with("class Saltybox < Formula\n")
    );
    assert!(
        fs::read_to_string(output.join("treeward.rb"))
            .unwrap()
            .starts_with("class Treeward < Formula\n")
    );
}

#[test]
/// An unregistered tool must be rejected before any download, whether it arrives on the
/// command line or in the configuration.
fn unregistered_tool_is_rejected_before_fetch() {
    let directory = tempdir().unwrap();
    let config_path = directory.path().join("pull.toml");
    let output = directory.path().join("Formula");
    write_config(&config_path, &config(None));
    let fixtures = Fixtures::for_tag("v1.2.3");

    let error = run_from(
        update_cli_for("juggler", &config_path, &output, "v1.2.3", false),
        directory.path(),
        &fixtures,
        &RealFileOps,
    )
    .unwrap_err();
    assert!(error.to_string().contains("unsupported tool: juggler"));
    assert_eq!(fixtures.calls.get(), 0);

    let configured =
        "schema_version = 1\n\n[tools.juggler]\ntag = \"v1.2.3\"\n\n[tools.juggler.sha256]\n";
    let parsed: Config = toml::from_str(configured).unwrap();
    // The configuration path wraps the cause in a "configured tool" context, so the
    // alternate formatting is needed to see the root diagnostic.
    let error = validate_config(&parsed).unwrap_err();
    assert!(format!("{error:#}").contains("unsupported tool: juggler"));
}

// Treeward-specific spellings used throughout the older tests. They live here
// rather than in the production module because they exist only to keep those
// call sites readable; production code always goes through a `ToolSpec`.
fn treeward_url(tag: &str, target: &str) -> String {
    release_url(&TREEWARD, tag, target)
}

fn validate_treeward_archive(bytes: &[u8], target: &str) -> Result<()> {
    validate_archive(&TREEWARD, bytes, target)
}

fn validate_treeward_archive_with_limits(
    bytes: &[u8],
    target: &str,
    limits: ArchiveLimits,
) -> Result<()> {
    validate_archive_with_limits(&TREEWARD, bytes, target, limits)
}

fn render_treeward(tool: &Tool) -> Result<String> {
    render(&TREEWARD, tool)
}

#[test]
/// Homebrew derives the Ruby class from the file name, so a hand-maintained
/// `class_name` that disagrees with `name` produces a formula Homebrew refuses to
/// load. Every registered tool's rendered formula must open with the class Homebrew
/// expects, and its install line and URLs must use the same name.
fn every_tool_renders_the_class_homebrew_expects() {
    for spec in TOOLS {
        let fixtures = Fixtures::for_tools(&[(spec, "v9.9.9")]);
        let tool = selected_for(spec, "v9.9.9", &fixtures);
        let formula = render(spec, &tool).unwrap();
        let mut expected_class = spec.name.chars();
        let expected_class: String = expected_class
            .next()
            .map(|first| first.to_ascii_uppercase())
            .into_iter()
            .chain(expected_class)
            .collect();
        assert_eq!(expected_class, spec.class_name, "{}", spec.name);
        assert!(formula.starts_with(&format!("class {expected_class} < Formula\n")));
        assert!(formula.contains(&format!("bin.install \"{}\"", spec.name)));
        assert!(formula.contains(&format!("/{}-x86_64-apple-darwin.tar.xz", spec.name)));
        assert!(formula.contains("  test do\n"));
    }
}
