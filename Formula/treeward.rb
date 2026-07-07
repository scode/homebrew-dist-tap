class Treeward < Formula
  desc "A command line tool for checksumming and verifying trees of files"
  homepage "https://github.com/scode/treeward"
  version "0.3.2"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.3.2/treeward-aarch64-apple-darwin.tar.xz"
      sha256 "07d9e5de8ee5369c7e6bd3e402cefe2de888269eeafcda3e0af6e4674c9406c1"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.3.2/treeward-x86_64-apple-darwin.tar.xz"
      sha256 "700d9c0960d6414ad2c8f40c17de34c9e743beefcc86f1c9bed06052cdc14649"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.3.2/treeward-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "9af756b6a39db2ca5fc13f4a4cddc177048aa3f99eb0771a72eb1f38c2e2042a"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.3.2/treeward-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "6f99269a5455fe479e776d46ef2ce3b1b70ab6c5a36456ae4e7815ef178b55cd"
    end
  end
  license any_of: ["MIT", "Apache-2.0"]

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
    bin.install "treeward" if OS.mac? && Hardware::CPU.arm?
    bin.install "treeward" if OS.mac? && Hardware::CPU.intel?
    bin.install "treeward" if OS.linux? && Hardware::CPU.arm?
    bin.install "treeward" if OS.linux? && Hardware::CPU.intel?

    install_binary_aliases!

    # Homebrew will automatically install these, so we don't need to do that
    doc_files = Dir["README.*", "readme.*", "LICENSE", "LICENSE.*", "CHANGELOG.*"]
    leftover_contents = Dir["*"] - doc_files

    # Install any leftover files in pkgshare; these are probably config or
    # sample files.
    pkgshare.install(*leftover_contents) unless leftover_contents.empty?
  end
end
