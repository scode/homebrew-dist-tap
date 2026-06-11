class Saltybox < Formula
  desc "Passphrase-based file encryption tool using NaCl secretbox"
  homepage "https://github.com/scode/saltybox"
  version "3.3.1"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.3.1/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "a6828dc0c3cd0ae63bf16c385e8dd4bfede5abe8ceb0eea130635b2b5996701c"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.3.1/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "91c4164e6217a4250705bd93afee6756935c9e3a5f5f19642c2de4d51d434caf"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v3.3.1/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "09a755836aba48fb8f638272178776989f1dc97c493553828c3a1cb57951a41f"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v3.3.1/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "af85084eaf1e4ee455dfb8c1b1ba31405708e7da4250050c6acc13ea779e6c8c"
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
