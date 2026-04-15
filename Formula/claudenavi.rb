class Claudenavi < Formula
  desc "MegaMan Battle Network-inspired NetNavi companion for Claude Code"
  homepage "https://github.com/Topazoo/claudenavi"
  url "https://registry.npmjs.org/claudenavi/-/claudenavi-0.1.0.tgz"
  sha256 "fb80d9d339c7262bed5ed4345873a18639395b604a7c9baed8408629baab3d58"
  license "MIT"

  depends_on "node@22"
  depends_on "python@3.13" => :build # node-gyp fallback for better-sqlite3

  on_macos do
    resource "widget" do
      url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.1.0/ClaudeNavi-macos-universal.app.tar.gz"
      sha256 "dc32f9cf3d90dd0b50078e18dcd8e104fbd3bb87a0a3e1cf38636b8d0be5d6c6"
    end
  end

  on_linux do
    on_intel do
      resource "widget" do
        url "https://github.com/Topazoo/homebrew-claudenavi/releases/download/v0.1.0/ClaudeNavi-linux-x86_64.AppImage.tar.gz"
        sha256 "4c0484439e4dd0b832a916b53a204928d99a1957f550369453d60cb0e48df73e"
      end
    end
  end

  def install
    system "npm", "install", *std_npm_args

    # Explicit wrapper pinned to Homebrew's node — avoids #!/usr/bin/env node
    # resolving to nvm/system node with a different ABI (segfaults native modules)
    node = Formula["node@22"].opt_bin/"node"
    (bin/"claudenavi").write <<~EOS
      #!/bin/bash
      exec "#{node}" "#{libexec}/lib/node_modules/claudenavi/dist/index.js" "$@"
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
    # Verify the native SQLite module loads correctly
    node = Formula["node@22"].opt_bin/"node"
    system node, "-e",
      "require('#{libexec}/lib/node_modules/claudenavi/node_modules/better-sqlite3')"
  end
end
