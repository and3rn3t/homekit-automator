class HomekitAutomator < Formula
  desc "AI-powered HomeKit automation skill for OpenClaw"
  homepage "https://github.com/and3rn3t/homekit-automator"
  url "https://github.com/and3rn3t/homekit-automator/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER"
  license "MIT"

  depends_on :macos => :sonoma
  depends_on "swift" => :build
  depends_on "node" => :recommended

  def install
    cd "scripts/swift" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/homekitauto"
    end

    # Install MCP server
    libexec.install "scripts/mcp-server/index.js" => "mcp-server.js"
    libexec.install "scripts/mcp-server/package.json"

    # Install SKILL.md for OpenClaw
    share.install "SKILL.md"
    share.install "scripts/openclaw-plugin/plugin.json"
  end

  def caveats
    <<~EOS
      HomeKit Automator requires the HomeKitHelper companion app
      for HomeKit access. Build and install it separately:
        cd #{share}/homekit-automator
        ./scripts/build.sh --release --install

      To use with OpenClaw, register the skill:
        openclaw install homekit-automator
    EOS
  end

  test do
    assert_match "HomeKit Automator", shell_output("#{bin}/homekitauto --help")
  end
end
