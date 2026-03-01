class HomekitAutomator < Formula
  desc "AI-powered HomeKit automation skill for OpenClaw"
  homepage "https://github.com/and3rn3t/homekit-automator"
  url "https://github.com/and3rn3t/homekit-automator/archive/refs/tags/v1.1.1.tar.gz"
  
  sha256 "b2018224a9f9a47bce1dd360c19d9528d7e01b903a307e8b60f2fe3314ac752c"
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

    # Install skill.md for OpenClaw
    share.install "docs/skill.md"
    share.install "scripts/openclaw-plugin/plugin.json"
  end

  def caveats
    <<~EOS
      HomeKit Automator requires the HomeKitHelper companion app
      for HomeKit access. See the README for build instructions.

      Configuration is stored in:
        ~/Library/Application Support/homekit-automator/

      To use with OpenClaw, register the skill:
        openclaw install homekit-automator
    EOS
  end

  test do
    assert_match "HomeKit Automator", shell_output("#{bin}/homekitauto --help")
    assert_match version.to_s, shell_output("#{bin}/homekitauto --version")
  end
end
