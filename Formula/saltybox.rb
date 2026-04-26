class Saltybox < Formula
  desc "Passphrase-based file encryption tool using NaCl secretbox"
  homepage "https://github.com/scode/saltybox"
  version "3.2.1"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.2.1/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "4c1ed444b9dcffcdbdd510b6d53601f7f11741468b6758606a3a2dadd9fa44cb"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.2.1/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "1183c7c10ebc16696eb198ce6defbf378fb5a2d84a10418a24bfc7e0b98fccf9"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.2.1/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "90566c84cc0a2cf31c92e8e93a0a63c12a06dbbb59960b4cfeb6bb8312508242"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.2.1/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "918d0ece2ab39a544a7336ee140db6d33509094e9cf74b9ab21f4fedc1667bc2"
    end
  end
  license any_of: ["Apache-2.0", "MIT"]

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
    bin.install "saltybox" if OS.mac? && Hardware::CPU.arm?
    bin.install "saltybox" if OS.mac? && Hardware::CPU.intel?
    bin.install "saltybox" if OS.linux? && Hardware::CPU.arm?
    bin.install "saltybox" if OS.linux? && Hardware::CPU.intel?

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
