class Saltybox < Formula
  desc "Passphrase-based file encryption tool"
  homepage "https://github.com/scode/saltybox"
  version "4.0.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v4.0.0/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "e194170e4f9f6fc9fce37610df7ace60243cbd9c6600e604e7482074f86a4706"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v4.0.0/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "4b8e5b14e209c0c91e84e362f48d73af977724b7dd18bc7874a9f2377aaecd9a"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v4.0.0/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "a99fd74f0919189424a27aef7502ea709e4d46851dc9e333e1c3780eb234465b"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v4.0.0/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "4bf1a7618b15348e4dbfaec99153b94d742733b7a8a224b44d2852cdc315dc30"
    end
  end
  license any_of: ["Apache-2.0", "MIT"]

  BINARY_ALIASES = {
    "aarch64-apple-darwin": {},
    "aarch64-unknown-linux-gnu": {},
    "x86_64-apple-darwin": {},
    "x86_64-unknown-linux-gnu": {}
  }

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
    if OS.mac? && Hardware::CPU.arm?
      bin.install "saltybox"
    end
    if OS.mac? && Hardware::CPU.intel?
      bin.install "saltybox"
    end
    if OS.linux? && Hardware::CPU.arm?
      bin.install "saltybox"
    end
    if OS.linux? && Hardware::CPU.intel?
      bin.install "saltybox"
    end

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
