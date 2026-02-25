cask "nicevoice" do
  version "0.1.0"
  sha256 "59bc4c8baefb8b83b3da6de1a49af53faa46470c8958e7bf59710ff582fd1f3f"

  url "https://github.com/schroneko/homebrew-tap/releases/download/v#{version}/NiceVoice-#{version}.zip"
  name "NiceVoice"
  desc "Voice input app for macOS"
  homepage "https://github.com/schroneko/nicevoice-app"

  depends_on formula: "uv"

  app "NiceVoice.app"

  zap trash: [
    "~/Library/Logs/NiceVoice",
  ]
end
