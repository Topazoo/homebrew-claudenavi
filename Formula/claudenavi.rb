class Claudenavi < Formula
  desc "MegaMan Battle Network-inspired NetNavi companion for Claude Code"
  homepage "https://github.com/Topazoo/claudenavi"
  url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.19/claudenavi-daemon-universal-apple-darwin.tar.gz"
  sha256 "71782c813439e9ccb97ab15d865f8ca20b906a463f67ff92a6afe97b4141627a"
  version "0.2.19"
  license "MIT"

  depends_on "node@22"

  on_linux do
    depends_on "python@3.13" => :build # node-gyp fallback for better-sqlite3

    on_intel do
      resource "widget" do
        url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.19/ClaudeNavi-linux-x86_64.AppImage.tar.gz"
        sha256 "09192f4aa326c0d1006cd39be598535397f17d7a355a3575abb33707001d3ad7"
      end
    end
  end

  on_macos do
    resource "widget" do
      url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.19/ClaudeNavi-macos-universal.app.tar.gz"
      sha256 "ce0b749ab010e2fdb30c48bd84e6c042159cbecfca4006fe0cbec616237e4071"
    end
  end

  def install
    pkg = libexec/"lib/node_modules/claudenavi"
    pkg.install Dir["*"]
    pkg.install ".claude" if File.directory?(".claude")

    # Explicit wrapper pinned to Homebrew's node — avoids #!/usr/bin/env node
    # resolving to nvm/system node with a different ABI (segfaults native modules)
    node = Formula["node@22"].opt_bin/"node"
    (bin/"claudenavi").write <<~EOS
      #!/bin/bash
      exec "#{node}" "#{libexec}/lib/node_modules/claudenavi/dist/index.js" "$@"
    EOS
    (bin/"claudenavi").chmod 0755

    # The daemon bundle ships a universal macOS better-sqlite3 binding. On
    # Linux, rebuild the native module for Homebrew's node@22 in-place.
    if OS.linux?
      system "npm", "rebuild", "better-sqlite3", "--prefix", pkg
    end

    # Widget: extract pre-built binary into libexec for post_install to copy
    if OS.mac?
      resource("widget").stage do
        (libexec/"ClaudeNavi.app").install Dir["ClaudeNavi.app/*"]
      end
    elsif OS.linux? && Hardware::CPU.intel?
      resource("widget").stage do
        libexec.install "ClaudeNavi.AppImage"
      end
    end
  end

  service do
    run [
      Formula["node@22"].opt_bin/"node",
      opt_libexec/"lib/node_modules/claudenavi/dist/index.js",
      "daemon", "run",
    ]
    keep_alive true
    log_path var/"log/claudenavi/daemon.log"
    error_log_path var/"log/claudenavi/daemon.log"
    working_dir var/"claudenavi"
  end

  def post_install
    (var/"claudenavi").mkpath
    (var/"log/claudenavi").mkpath

    # Set up hooks, MCP, hatch Navi.
    # --skip-daemon: brew services manages the LaunchAgent/systemd unit
    # --skip-widget: pre-built widget is already downloaded by the formula
    system bin/"claudenavi", "install", "--yes",
           "--skip-daemon", "--skip-widget"

    # Install widget to the platform-appropriate location
    if OS.mac? && File.directory?("#{libexec}/ClaudeNavi.app")
      app_dest = "#{Dir.home}/Applications/ClaudeNavi.app"
      FileUtils.mkdir_p("#{Dir.home}/Applications")
      FileUtils.rm_rf(app_dest) if File.exist?(app_dest)
      FileUtils.cp_r("#{libexec}/ClaudeNavi.app", app_dest)
    elsif OS.linux? && File.exist?("#{libexec}/ClaudeNavi.AppImage")
      bin_dest = "#{Dir.home}/.local/bin"
      FileUtils.mkdir_p(bin_dest)
      FileUtils.cp("#{libexec}/ClaudeNavi.AppImage", "#{bin_dest}/ClaudeNavi.AppImage")
      FileUtils.chmod(0o755, "#{bin_dest}/ClaudeNavi.AppImage")
    end
  end

  def caveats
    widget_launch = if OS.mac?
      "  Desktop widget:\n    open ~/Applications/ClaudeNavi.app"
    elsif OS.linux? && Hardware::CPU.intel?
      "  Desktop widget (requires libfuse2):\n" \
      "    ~/.local/bin/ClaudeNavi.AppImage\n\n" \
      "    If you see \"error loading libfuse.so.2\":\n" \
      "      sudo apt install libfuse2     # Debian/Ubuntu\n" \
      "      # or: ClaudeNavi.AppImage --appimage-extract-and-run"
    else
      "  Desktop widget: not yet available on ARM64 Linux.\n" \
      "    The CLI and daemon work on all architectures."
    end

    <<~EOS

      ClaudeNavi is installed. Get started:

        brew services start claudenavi    # start the daemon
        claudenavi doctor                 # verify everything is healthy

      The daemon runs in the background, reacting to your Claude Code
      sessions automatically. It starts on login and restarts on crash.

      Commands:
        claudenavi status           # Navi state, daemon health
        claudenavi stats            # coding stats and level
        claudenavi chips            # Battle Chip collection
        claudenavi logs             # recent activity

    #{widget_launch}

      To fully remove ClaudeNavi:
        claudenavi uninstall --all
        brew services stop claudenavi
        brew uninstall claudenavi
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/claudenavi --version")
    # Verify the native SQLite module loads correctly
    node = Formula["node@22"].opt_bin/"node"
    system node, "-e",
      "require('#{libexec}/lib/node_modules/claudenavi/node_modules/better-sqlite3')"
  end
end
