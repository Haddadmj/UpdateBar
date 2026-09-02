# Homebrew cask for UpdateBar.
#
# Lives here as the source of truth; a tap serves it from a copy. To publish a
# new version: cut the GitHub release, then update version and sha256 below
#   shasum -a 256 .build/dist/UpdateBar.dmg
# and copy this file into Haddadmj/homebrew-tap as Casks/updatebar.rb.
cask "updatebar" do
  version "0.1.0"
  sha256 "0ea9f5a05d52d57e7d303f578110b475a7b5ba9b10bb97332b4d40f172a6a91b"

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
