class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.1.1"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.1.1/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "0549f4f93d37c767c5b0df0cdf15da01662014451e97d5f5d33c8d87ffadaa67"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.1.1/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "3e53482cfe3e016565076f9c95e596229fe49ccacc1c0c4655fac48dc5ff4824"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.1.1/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "204de11eb2d9bfbff9552dd920fd30abc2bd079cd556f368efcf313878edc053"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.1.1/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "3bdb8add4b054d0c184c6549628dc9650f021de77385d0263f2aa6139725f206"
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
