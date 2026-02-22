class Juggler < Formula
  desc "TODO juggler"
  homepage "https://github.com/scode/juggler"
  version "0.2.1"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.1/juggler-aarch64-apple-darwin.tar.xz"
      sha256 "2a13eb9b5e21b423cf2fab85c69e958b672e103ba587bae8260b45b7a5a8323b"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.1/juggler-x86_64-apple-darwin.tar.xz"
      sha256 "a12739e788f1ea731fd813582f2a9cb06cf293c5c310e909699ebd72e01567f8"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.1/juggler-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "aa23b83934db2cb100147b8c6006a200b0561465701b2cb1cbc34d3cdad6038b"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.1/juggler-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "a45e903b73e623affd483bdd6c348602e6c675e184fdded8fe1089e446df3cff"
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
