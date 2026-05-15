class Claudenavi < Formula
  desc "MegaMan Battle Network-inspired NetNavi companion for Claude Code"
  homepage "https://github.com/Topazoo/claudenavi"
  url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.9/claudenavi-daemon-universal-apple-darwin.tar.gz"
  sha256 "4c7bce72f87276649a7640719c0c826cf2ca150656cb743c18dd64672d52df0d"
  version "0.2.9"
  license "MIT"

  depends_on "node@22"

  on_macos do
    resource "widget" do
      url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.9/ClaudeNavi-macos-universal.app.tar.gz"
      sha256 "e1ce0384825fcc4eaf682a4dbc10a8fa56a495fc7c042ca47f7931d3dee76633"
    end
  end

  on_linux do
    on_intel do
      resource "widget" do
        url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.2.9/ClaudeNavi-linux-x86_64.AppImage.tar.gz"
        sha256 "f94cc8acc0504d063ac36b2f3742dd7164c1907e19ff657bc1ea3eb9dcc3a1a1"
      end
    end
  end

  def install
    # The daemon-bundle tarball is already an installed npm package: it ships
    # dist/, node_modules/ (production-only), and package.json — with a
    # universal better_sqlite3.node baked in. So `brew install` is now just
    # tarball extraction: no node-gyp, no python build dep, no per-machine
    # rebuild of native modules.
    target = libexec/"lib/node_modules/claudenavi"
    target.mkpath
    target.install Dir["*"]

    # Explicit wrapper pinned to Homebrew's node — avoids #!/usr/bin/env node
    # resolving to nvm/system node with a different ABI (segfaults native modules)
    node = Formula["node@22"].opt_bin/"node"
    (bin/"claudenavi").write <<~EOS
      #!/bin/bash
      exec "#{node}" "#{target}/dist/index.js" "$@"
    EOS

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
    # Verify the bundled universal SQLite module loads correctly
    node = Formula["node@22"].opt_bin/"node"
    system node, "-e",
      "require('#{libexec}/lib/node_modules/claudenavi/node_modules/better-sqlite3')"
  end
end
