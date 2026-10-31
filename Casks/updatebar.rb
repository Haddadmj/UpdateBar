# Homebrew cask for UpdateBar.
#
# Lives here as the source of truth; a tap serves it from a copy. To publish a
# new version: cut the GitHub release, then update version and sha256 below
#   shasum -a 256 .build/dist/UpdateBar.dmg
# and copy this file into Haddadmj/homebrew-tap as Casks/updatebar.rb.
cask "updatebar" do
  version "0.2.1"
  sha256 "842962401be06ecc187c64fb0fbaacab1ed5c7dac88e97e5606365aa5346f59e"

  url "https://github.com/Haddadmj/UpdateBar/releases/download/v#{version}/UpdateBar.dmg"
  name "UpdateBar"
  desc "Menu-bar aggregator of pending updates across package managers and app stores"
  homepage "https://github.com/Haddadmj/UpdateBar"

  depends_on macos: :sonoma

  app "UpdateBar.app"

  # Registered with SMAppService when launch-at-login is on, so uninstalling
  # without unregistering would leave a login item pointing at a missing app.
  uninstall quit:       "com.updatebar.app",
            login_item: "UpdateBar"

  zap trash: [
    "~/Library/Caches/com.updatebar.app",
    "~/Library/Preferences/com.updatebar.app.plist",
    "~/Library/Saved Application State/com.updatebar.app.savedState",
  ]
end
