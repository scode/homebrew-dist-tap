class Juggler < Formula
  desc "TODO juggler"
  homepage "https://github.com/scode/juggler"
  version "0.2.4"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.4/juggler-aarch64-apple-darwin.tar.xz"
      sha256 "42bc20767b23207a7994a9e615d4ddf7a239cb7958b373ed4c4868e9fc4c4692"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.4/juggler-x86_64-apple-darwin.tar.xz"
      sha256 "810df3649a3d0d2479e9e0661dadb646fb60aafed53e67eb9e526220abf1f0d4"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.4/juggler-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "d8be9f9d9574ecd4d4a40eca89986f18f4e7d1fbb7b2a096c28cd8d481f5adb5"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.4/juggler-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "649a93e4dcc18bc602cbdc9517ec9766bd7012a3a69efb03dcfeaff2d84987d2"
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
