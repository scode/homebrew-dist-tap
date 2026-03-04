class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.5.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.5.0/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "976c60dd5b2aac8833bc81ff97ebf1196504931941ee574788e4d9e78e39b03d"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.5.0/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "0e192181aa41c0e5ce5c4e6701a8ebc3336b501a6c5bca304316c2451ccf66e0"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.5.0/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "4f288537d425b9b95aa98a0dc13261b577071701f5487083ac4a38f995877ecf"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.5.0/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "ad8b3e98981f86e20d8686a185d863f6bc9661a7620852f80f56f295137abede"
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
