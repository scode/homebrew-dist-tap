class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.3.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.3.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "4990ab207cf40cae819da42408d7e2fefa662a7607cb381de5f6802ff840e5a2"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.3.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "eb11916f49f0ac75706f3297b396cb978ffbc95c27888ee1d1e2f398373937b0"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.3.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "24c93e9bc4d5b38233dcd155306ec42675a09ecf9e20484f94a849e8b96a5996"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.3.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "93a13a7640de88b758dea9601bcc49ca859ecca53ed5412b29e55d0c1f2a6b82"
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
