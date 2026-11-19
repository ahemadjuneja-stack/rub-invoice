# OTA Updates (two pipelines)

## Pipeline 1 - GitHub Releases APK (implemented, zero extra accounts)

`.github/workflows/android.yml` does:

* every push / PR: analyze + release APK build, APK uploaded as a CI artifact
* every `v*` tag: APK published to a **GitHub Release** automatically

**Publish a new version:**

```bash
# 1. bump version in pubspec.yaml (e.g. 0.1.1+2)
git add pubspec.yaml
git commit -m "Bump version to 0.1.1"
git tag v0.1.1
git push origin main --tags
# Actions builds the APK and attaches it to the v0.1.1 release
```

**In-app updates (background download + one-tap install):** the app checks
`api.github.com/repos/ahemadjuneja-stack/rub-invoice/releases/latest`
silently at most once every 6 hours and from *Menu -> Check Updates*. When
a newer tag is found, the release APK downloads in the background (progress
banner on the Billing tab); when done the user just taps **Install** -
`open_filex` hands the file to the Android package installer
(`REQUEST_INSTALL_PACKAGES` is already declared).

> Note: this pipeline is for APK distribution outside the Play Store
> (direct-to-customer, WhatsApp groups, website). The Play Store has its
> own update mechanism.

## Pipeline 2 - Shorebird (true OTA Dart patches, optional)

Shorebird pushes **Dart code patches** without reinstalling the APK -
the user sees the update the next time the app opens. Native/asset
changes still need a normal release. Free tier available.

```bash
# one time
curl -s https://api.shorebird.dev/install.sh | bash     # or: flutter pub global activate shorebird_cli
shorebird login
shorebird init          # creates shorebird.yaml in the repo; commit it
shorebird doctor

# release a new version (produces the same APK as flutter build, plus a patch channel)
shorebird release aosp --flutter-version=$(flutter --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

# later, ship a hotfix without asking users to reinstall:
#  - edit Dart code
#  - bump pubspec version
shorebird patch aosp --release-version=0.1.1+2
```

Requirements/notes:

* A Shorebird account (free) and `shorebird.yaml` committed to the repo.
* Users must install APKs built by `shorebird release` (not plain
  `flutter build`) to be patchable.
* Keep the first shorebird release version in sync with your GitHub
  Release tag so both pipelines point to the same install base.

Recommended flow: GitHub Releases for full APK updates (native +
assets + Dart), Shorebird patches for Dart-only hotfixes.
