cask "nicevoice" do
  version "0.2.0"
  sha256 "0a3146ca79b988f574aa5cd0559bf39784b96e1fdd289826dc7b05ea27cd73a6"

  url "https://github.com/schroneko/homebrew-nicevoice/releases/download/v#{version}/NiceVoice-#{version}.zip"
  name "NiceVoice"
  desc "Voice input app for macOS"
  homepage "https://github.com/schroneko/homebrew-nicevoice"

  app "NiceVoice.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "/Applications/NiceVoice.app"],
                   sudo: false
  end

  uninstall quit: "app.nicevoice.NiceVoice"

  zap trash: [
    "~/Library/Logs/NiceVoice",
    "~/Library/Preferences/app.nicevoice.NiceVoice.plist",
  ]
end
