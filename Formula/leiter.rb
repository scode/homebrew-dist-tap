class Leiter < Formula
  desc "A self-training system for Claude Code"
  homepage "https://github.com/scode/leiter"
  version "0.8.1"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.8.1/leiter-aarch64-apple-darwin.tar.xz"
      sha256 "f9a8d05d25189746937796618b31c8f65fc11fad842c37ad6195f56e24564772"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.8.1/leiter-x86_64-apple-darwin.tar.xz"
      sha256 "6b44b95018420cad5e4684a9f0b064fc6cfb329d4af1820815d287be5d0829fc"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/leiter/releases/download/v0.8.1/leiter-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "6e4a3bb8f225e918864645edce3b09c4bf0f02bf5a37a9e671dd094fa22fdeaf"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/leiter/releases/download/v0.8.1/leiter-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "f73d4324093cdb85702b451678d0824d33a00fe245c9319db56f980f77ea6bfb"
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
