# Template for Casks/open1000x.rb in github.com/gergogyulai/homebrew-tap.
# The release workflow fills in the version and checksum and pushes it there.
cask "open1000x" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/gergogyulai/open1000x/releases/download/v#{version}/Open1000X-#{version}.zip"
  name "Open1000X"
  desc "Menu bar app for Sony 1000X headphones"
  homepage "https://github.com/gergogyulai/open1000x"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Open1000X.app"
  binary "#{appdir}/Open1000X.app/Contents/MacOS/mdrctl"

  # The app isn't notarized (no paid Apple developer account). Without this, Gatekeeper blocks the first
  # launch and the user has to allow it in System Settings → Privacy & Security.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Open1000X.app"],
        writable_paths: ["Open1000X.app"],
        writable_base:  :appdir
  end

  uninstall quit:       "dev.open1000x.app",
            login_item: "Open1000X"

  zap trash: "~/Library/Preferences/dev.open1000x.app.plist"
end
