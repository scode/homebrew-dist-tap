class Treeward < Formula
  desc "A command line tool for checksumming and verifying trees of files"
  homepage "https://github.com/scode/treeward"
  version "0.3.3"
  license any_of: ["MIT", "Apache-2.0"]

  on_macos do
    on_arm do
      url "https://github.com/scode/treeward/releases/download/v0.3.3/treeward-aarch64-apple-darwin.tar.xz"
      sha256 "9710b1888ea6b5897fac24ee4bcc37677b369ab67a6dacde38a50339310276ee"
    end

    on_intel do
      url "https://github.com/scode/treeward/releases/download/v0.3.3/treeward-x86_64-apple-darwin.tar.xz"
      sha256 "4132cfefac9629cc8ef4c8086bc12fddb53a1569ab824ca650c8332fd6b90742"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/scode/treeward/releases/download/v0.3.3/treeward-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "2a916a36d1e14f5a82dbc8e26d96ca437f949cacdf2979e5346bc76bf46f84e6"
    end

    on_intel do
      url "https://github.com/scode/treeward/releases/download/v0.3.3/treeward-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "b0246b228add03ff34804eb48f125ba9bd8dfc9df62e8bd9a34f6e3101e0d231"
    end
  end

  def install
    bin.install "treeward"
    doc.install "README.md", "CHANGELOG.md", "LICENSE"
  end

  test do
    (testpath/"content").write "original"
    system bin/"treeward", "init"
    system bin/"treeward", "verify"
    File.write(testpath/"content", "changed")
    assert_match "Verification failed", shell_output("#{bin}/treeward verify 2>&1", 1)
  end
end
