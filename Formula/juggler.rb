class Juggler < Formula
  desc "Terminal TODO manager with TOML storage and Google Tasks sync"
  homepage "https://github.com/scode/juggler"
  version "0.2.7"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/scode/juggler/releases/download/v0.2.7/juggler-aarch64-apple-darwin.tar.xz"
      sha256 "618599d491c9cac5e4edbbbe08dee5f59fbec9465080f4a16ecb424ce5843d19"
    end

    on_intel do
      url "https://github.com/scode/juggler/releases/download/v0.2.7/juggler-x86_64-apple-darwin.tar.xz"
      sha256 "6b0495d0f4d2af5673cf478cf7d1127093cbd088cb299064ecbe1fee3ed78878"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/scode/juggler/releases/download/v0.2.7/juggler-aarch64-unknown-linux-gnu.tar.xz"
      sha256 "6ce00d1ebcd3fe130613c1225bdd77af3ac84f29a54ffa66839d1bbd2640759c"
    end

    on_intel do
      url "https://github.com/scode/juggler/releases/download/v0.2.7/juggler-x86_64-unknown-linux-gnu.tar.xz"
      sha256 "97fde94fa6253059741a42a79816f757446913ea678090d9fd8bb0e218068c8c"
    end
  end

  def install
    bin.install "juggler"
    doc.install "README.md", "CHANGELOG.md", "LICENSE"
  end

  test do
    state = testpath/"state"
    state.mkpath
    store = state/"TODOs.toml"
    store.write <<~TOML
      [metadata]
      format_version = 2
      juggler_edition = 1

      [todos.T1]
      title = "Homebrew fixture"
      done = false
    TOML

    command = "'#{bin}/juggler' --juggler-dir '#{state}' " \
              "--google-oauth-client-id ' ' --google-oauth-client-secret ' ' " \
              "sync google-tasks --dry-run 2>&1"
    assert_match "unsupported metadata.format_version=2 (expected 1)", shell_output(command, 1)

    File.write(store, store.read.sub("format_version = 2", "format_version = 1"))
    original = store.read
    assert_match "Missing Google OAuth client id", shell_output(command, 1)
    assert_equal original, store.read
    assert_equal ["TODOs.toml"], state.children.map { |path| path.basename.to_s }.sort
  end
end
