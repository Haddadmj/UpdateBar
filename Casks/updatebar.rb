# Homebrew cask for UpdateBar.
# Publish by hosting the notarized DMG (e.g. on a GitHub release) and filling in the
# version, url, and sha256 below, then submit to a tap:
#   brew tap Haddadmj/tap && brew install --cask updatebar
cask "updatebar" do
  version "0.1.0"
  sha256 :no_check # replace with the DMG's shasum -a 256 once published

  url "https://github.com/Haddadmj/UpdateBar/releases/download/v#{version}/UpdateBar.dmg"
  name "UpdateBar"
  desc "Menu-bar aggregator of pending updates across package managers and app stores"
  homepage "https://github.com/Haddadmj/UpdateBar"

  depends_on macos: ">= :sonoma"

  app "UpdateBar.app"

  zap trash: [
    "~/Library/Preferences/com.updatebar.app.plist",
  ]
end
