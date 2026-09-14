class Saltybox < Formula
  desc "Passphrase-based file encryption tool"
  homepage "https://github.com/scode/saltybox"
  version "5.0.1"
  license any_of: ["Apache-2.0", "MIT"]

  on_macos do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v5.0.1/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "bac50d57cfb160a683008ab9bd92c3da79096372d754b9c094610c8542f0e334"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v5.0.1/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "e7c86ab7cfaf4fa35fc6c34cb7baccf40cfec774b87e3c473c48a64e82e416fa"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v5.0.1/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "7e7f88dbc6f00c1044e6c8484922801103dcffdd49e4f4be831338817d06593d"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v5.0.1/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "ac33a5485cad2e7949603d59e590c52104eaf411a45ebce71f569b948fa68102"
    end
  end

  def install
    bin.install "saltybox"
    doc.install "README.md", "CHANGELOG.md", "LICENSE"
  end

  test do
    (testpath/"secret.txt").write "top secret"
    pipe_output("#{bin}/saltybox --passphrase-stdin encrypt -i secret.txt -o secret.saltybox", "correct horse", 0)
    pipe_output("#{bin}/saltybox --passphrase-stdin decrypt -i secret.saltybox -o roundtrip.txt", "correct horse", 0)
    assert_equal "top secret", (testpath/"roundtrip.txt").read
    wrong = pipe_output("#{bin}/saltybox --passphrase-stdin decrypt -i secret.saltybox -o wrong.txt 2>&1", "wrong", 1)
    assert_match "failed to decrypt", wrong
    refute_path_exists testpath/"wrong.txt"
  end
end
