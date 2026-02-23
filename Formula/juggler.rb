class Juggler < Formula
  desc "TODO juggler"
  homepage "https://github.com/scode/juggler"
  version "0.2.5"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.5/juggler-aarch64-apple-darwin.tar.xz"
      sha256 "38ee401d21c3511c2f486734fdb5b7eb214e27034bf93d25a0d66898e40c3625"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.5/juggler-x86_64-apple-darwin.tar.xz"
      sha256 "dae432a7a4afc1ad2cbf744bd53199d34964a24a157236d273051de4ba996197"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/juggler/releases/download/v0.2.5/juggler-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "1e898424f3085ceca6f4883bde73353b7b23be90dc19d8cb1520658f5b85feb4"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/juggler/releases/download/v0.2.5/juggler-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "fe9ef50ade2637adafbeb1db28d645fef982ee484c719ef583c08f16da701f6d"
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
