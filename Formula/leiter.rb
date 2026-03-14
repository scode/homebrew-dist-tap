class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.7.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.7.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "c903483f38795c6faff25051690b14be5a4b2528c4c60a51b50b2b960db28070"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.7.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "1a438c7ed93708bd4b56157e39369745afc621698b896d74000b5d4cacaa384f"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.7.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "781a4ebfbde56a5207f5f7480e45cd85c43f08f7b056c0a9eaa236a433aa79ec"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.7.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "adc3311ff31871678ee4c2541feb578669f1d279b761cc71f271f78943f76c71"
    end
  end

  BINARY_ALIASES = {
    "aarch64-apple-darwin":      {},
    "aarch64-unknown-linux-gnu": {},
    "x86_64-apple-darwin":       {},
    "x86_64-unknown-linux-gnu":  {},
  }.freeze

  def target_triple
    cpu = Hardware::CPU.arm? ? "aarch64" : "x86_64"
    os = OS.mac? ? "apple-darwin" : "unknown-linux-gnu"

    "#{cpu}-#{os}"
  end

  def install_binary_aliases!
    BINARY_ALIASES[target_triple.to_sym].each do |source, dests|
      dests.each do |dest|
        bin.install_symlink bin/source.to_s => dest
      end
    end
  end

  def install
    bin.install "leiter" if OS.mac? && Hardware::CPU.arm?
    bin.install "leiter" if OS.mac? && Hardware::CPU.intel?
    bin.install "leiter" if OS.linux? && Hardware::CPU.arm?
    bin.install "leiter" if OS.linux? && Hardware::CPU.intel?

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
