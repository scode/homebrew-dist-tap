class Saltybox < Formula
  desc "Passphrase-based file encryption tool using NaCl secretbox"
  homepage "https://github.com/scode/saltybox"
  version "3.3.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.3.0/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "cc3b7ef2d85ebcd464f2e6ad19c26afc01bcfa4a0607e893bf7cae660b2c882a"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.3.0/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "a1d4c1e1d27451aeba8627e18fc2c58e1194a4c5548a6c959d16dd676a60c387"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.3.0/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "6642c54f0c47ec1ec0b51b8b5aade0657921f898b39579003c92f529ea0d5fdd"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.3.0/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "84cd0686965ec6d276e8f43f0865a16b2032b6d647cb4678d6dde365cf9b882e"
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
