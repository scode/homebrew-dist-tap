class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.2.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.2.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "c76ff2053e66fafc414ed93de17b9e2aa6c1910bb1caf584726e2384f1e962ab"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.2.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "5c8ab922011b21753cdfbb2dea2f8e9a5131789014ec4d2cb1e8ad0a5adac017"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.2.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "8ece1e04e43a5fe460d82c07a282db4ab8108fb38ea440418667fd0054957e9d"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.2.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "d46eeb4cda046c8fadbfaa3926166b312734ad0865554a816eff2f4be57be3b9"
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
