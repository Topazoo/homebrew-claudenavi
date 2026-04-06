class Claudenavi < Formula
  desc "MegaMan Battle Network-inspired NetNavi companion for Claude Code"
  homepage "https://github.com/pswanson/claudenavi"
  url "https://github.com/pswanson/claudenavi/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER"
  version "0.1.0"
  license "MIT"

  depends_on "node@20"

  def install
    # Install dependencies with locked versions, no lifecycle scripts
    # (supply chain: prevents arbitrary code execution during npm install)
    system "npm", "ci", "--ignore-scripts"

    # Compile TypeScript to dist/
    system "npm", "run", "build"

    # Install everything to libexec (node_modules + dist stay together)
    libexec.install Dir["*"]
    libexec.install ".claude" if File.directory?(".claude")

    # Create wrapper script that uses Homebrew's node
    node = Formula["node@20"].opt_bin/"node"
    (bin/"claudenavi").write <<~EOS
      #!/bin/bash
      exec "#{node}" "#{libexec}/dist/index.js" "$@"
    EOS
  end

  def post_install
    # Run the install command to set up hooks, LaunchAgent, MCP, etc.
    # --yes skips interactive prompts
    system bin/"claudenavi", "install", "--yes"
  end

  def caveats
    <<~EOS
      ClaudeNavi has been installed and the daemon is starting.

      Quick check:
        claudenavi doctor

      The PostToolUse hook has been registered in ~/.claude/settings.json.
      The daemon runs as a LaunchAgent and starts automatically on login.

      Your Navi's data lives in ~/.claudenavi/ and is preserved across upgrades.

      To install the desktop widget (requires Rust toolchain):
        cd #{libexec} && npx tauri build
    EOS
  end

  test do
    assert_match "claudenavi", shell_output("#{bin}/claudenavi --version")
  end
end
