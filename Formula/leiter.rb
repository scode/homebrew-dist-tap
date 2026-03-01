class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.4.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.4.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "e5d1ac9656ca01cdb6789a686e0b5ccdf7fe1aa7749f9228f9d338560b320991"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.4.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "90d2781da7cf8db8ca6b4d91d646f649e2d6e111ddaaea8fa91d322cb7689b86"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.4.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "8257db57270038f2006c701070c66f68710e8d79a1b002c1926eb23ec287f9c8"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.4.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "9e50379205012d4e2eccadc15298ccb76aec2700531a023f3312d6765c9fbb9a"
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
