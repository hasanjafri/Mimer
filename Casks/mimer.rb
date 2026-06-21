cask "mimer" do
  version "0.1.0"
  sha256 "e4e2ebffcf6a41f0f1a7bdd7fb9233ea857da8894b2de7305163f7fdccd36397"

  url "https://github.com/hasanjafri/Mimer/releases/download/v#{version}/Mimer-#{version}.dmg",
      verified: "github.com/hasanjafri/Mimer/"
  name "Mimer"
  desc "Fast, private, developer-first clipboard manager"
  homepage "https://github.com/hasanjafri/Mimer"

  depends_on macos: ">= :sonoma"

  app "Mimer.app"

  zap trash: [
    "~/Library/Application Support/Mimer",
    "~/Library/Preferences/com.hasanjafri.Mimer.plist",
  ]
end
