class Saltybox < Formula
  desc "Passphrase-based file encryption tool"
  homepage "https://github.com/scode/saltybox"
  version "5.0.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v5.0.0/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "846c58a66356919c2d0ea38a18867e0d92f894d4164fa7493e39f423dbc2f425"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v5.0.0/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "cb7e1774c92150b3a5b1aaf950650dbae17dae0110e38a007b555039719bc33d"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/saltybox/releases/download/v5.0.0/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "41f3d14889ab1f4e34389df103c5a331871d6e8d4f884ccf7aeb4aa25dbc55fa"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/saltybox/releases/download/v5.0.0/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "1df04989ea6c796399ba0000a531b31e14619f7b05cc8c4581474e6efa4053d1"
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
