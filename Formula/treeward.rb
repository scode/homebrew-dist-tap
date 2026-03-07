class Treeward < Formula
  desc "A command line tool for checksumming and verifying trees of files"
  homepage "https://github.com/scode/treeward"
  version "0.2.0"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.2.0/treeward-aarch64-apple-darwin.tar.xz"
      sha256 "590461c941485fd930df8fd92ecb2a15cb1157670e752c632cccddb7729c0b9a"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.2.0/treeward-x86_64-apple-darwin.tar.xz"
      sha256 "018f347f19f40f054c0ca9d90d69126edeae76adae94b9acba245077541cba70"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/scode/treeward/releases/download/v0.2.0/treeward-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "8ef6b564b3a9ab4a66f8786a413a3b6f1ab7c10af815c9b9766b759a81624518"
    end
    if Hardware::CPU.intel?
      url "https://github.com/scode/treeward/releases/download/v0.2.0/treeward-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "26889cf088f2f837762f4655a82acfe3ceee4220b03006caa598e15874913ebd"
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
