class Juggler < Formula
  desc "TODO juggler"
  homepage "https://github.com/scode/juggler"
  version "0.2.2"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.2/juggler-aarch64-apple-darwin.tar.xz"
      sha256 "68ee7d5dab386b248d4ca92b8d1548470afed89476c3b790fe1e89f00cee12d3"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.2/juggler-x86_64-apple-darwin.tar.xz"
      sha256 "180dface85942edb0d0d386c302fa581477a0d03b29144f9cc9591c799396c62"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.2/juggler-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "ac3565a392c05f3d5e38073aaedb0fdd826fd4d7d0a525a2b70db4f620566b7d"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.2/juggler-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "9c7a07a286d477e98e4a69fd474468f8e4b8f03362c41a4aaab914a8baaaf9c3"
    end
  end
  license "MIT"

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
    bin.install "juggler" if OS.mac? && Hardware::CPU.arm?
    bin.install "juggler" if OS.mac? && Hardware::CPU.intel?
    bin.install "juggler" if OS.linux? && Hardware::CPU.arm?
    bin.install "juggler" if OS.linux? && Hardware::CPU.intel?

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
