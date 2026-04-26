class Treeward < Formula
  desc "A command line tool for checksumming and verifying trees of files"
  homepage "https://github.com/scode/treeward"
  version "0.3.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.3.0/treeward-aarch64-apple-darwin.tar.xz"
      sha256 "c3f3b27abdc9cae83225b9cfc58c4e9b6ae6a5b7c47268d79550534eb98608bb"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.3.0/treeward-x86_64-apple-darwin.tar.xz"
      sha256 "eb1acaec5d18fe5c8423a6d62ac1102af997ed7d2b388721629e62b56c7c19b3"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.3.0/treeward-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "5e180b7b3651201cd7eede19f39fcc94ad5550fca21a960196bba2b6be688ff5"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.3.0/treeward-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "a0e84325331a986c60ac38e72326019b7f7ca5ad46911dcf6e3f888c714d3390"
    end
  end
  license any_of: ["MIT", "Apache-2.0"]

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
    bin.install "treeward" if OS.mac? && Hardware::CPU.arm?
    bin.install "treeward" if OS.mac? && Hardware::CPU.intel?
    bin.install "treeward" if OS.linux? && Hardware::CPU.arm?
    bin.install "treeward" if OS.linux? && Hardware::CPU.intel?

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
