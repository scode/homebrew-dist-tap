class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.6.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.6.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "293b5b38178d4f64db3afdf31d27443b40dd61690572fd888665d27b6030f8aa"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.6.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "c8819d8f811a5aabfb90431a10a28dbac0561fb64ae5d740185b6b68109cd01b"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.6.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "ebadfffac4fdb97c9e4eb8de49c7813f526d40626836929b4eb29d8b0bfef972"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.6.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "51abc58e2f449918e30192f4958bb99b603381b0d295c1bfd6760e96756e2996"
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
