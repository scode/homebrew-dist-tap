class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.8.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.8.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "e4bb5f000a2d31b33ac252a5732eafb2f4e398b8a27d38fe19745c5fc2625d84"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.8.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "7a4a24a0cf7cf870a3a136cb0c996c0793f1325e028cd29b377c2da8262149bb"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.8.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "6208ea8197a4140201151259424b32b995f03014c66260eed51b2894d0728aa1"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.8.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "03df8a396784bd161e0222ea2301a73774f7e7d148ef014038acc08e5b055717"
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
