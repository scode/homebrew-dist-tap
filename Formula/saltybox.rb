class Saltybox < Formula
  desc "Passphrase-based file encryption tool"
  homepage "https://github.com/scode/saltybox"
  version "6.0.0"
  license any_of: ["Apache-2.0", "MIT"]

  on_macos do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v6.0.0/saltybox-aarch64-apple-darwin.tar.xz"
      sha256 "6bd91360989911b8d09a766d90a2dd17cdec6ae21ee9dda9cb5f8bd5b693af96"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v6.0.0/saltybox-x86_64-apple-darwin.tar.xz"
      sha256 "285be88b9da233ed8a6a3fee4a75bb57df0e5afefd98a9712779b6a431389d8d"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/scode/saltybox/releases/download/v6.0.0/saltybox-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "aed6e7dcc3a27ee79a937852e6edb3bfa8e9a88a7c98812bf960a75a3ec36a03"
    end

    on_intel do
      url "https://github.com/scode/saltybox/releases/download/v6.0.0/saltybox-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "41322fbc7fa89e283e0ff0d53b886489762182a86a352e8bf968a827106c48c6"
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
