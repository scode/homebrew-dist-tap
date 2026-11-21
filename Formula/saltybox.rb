class Saltybox < Formula
  desc "Passphrase-based file encryption tool"
  homepage "https://github.com/scode/saltybox"
  version "7.0.0"
  license any_of: ["Apache-2.0", "MIT"]

  on_macos do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v7.0.0/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "c5a81c4240fedc8d7ae1d2a4affb94a80e4f1c9bf4a7366c344429aeee91c49a"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v7.0.0/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "25e229024282ddfc5f6c95870da5cb6c4016ee896b9d6f3129b989f2461fd95b"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v7.0.0/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "242c009148cd6ea579d7fd36e43f9583b50375618248f800329003defb16895f"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v7.0.0/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "8ebc8acdfd7e485fe856e53b933fe54a63b73185408a3f77229387f05d3fd986"
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
