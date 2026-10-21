#!/bin/zsh
set -euo pipefail
setopt numeric_glob_sort

root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$root/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 "VERSION must use semantic versioning (for example 1.0.1)."; exit 1; }

output_dir="$root/dist"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-usage-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcodegen generate --spec "$root/project.yml"
xcodebuild \
  -project "$root/CodexUsage.xcodeproj" \
  -scheme CodexUsage \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$build_dir/derived-data" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$version" \
  CODE_SIGNING_ALLOWED=NO \
  build

app="$build_dir/derived-data/Build/Products/Release/ChatGPT Usage.app"
[[ -d "$app" ]] || { print -u2 "Expected app bundle was not built: $app"; exit 1; }

# Login Items requires a valid bundle signature; ad hoc signing does not verify a publisher.
codesign --force --sign - --options runtime --timestamp=none "$app"
codesign --verify --strict "$app"

staging="$build_dir/dmg-root"
mkdir -p "$staging"
ditto "$app" "$staging/ChatGPT Usage.app"
ditto "$root/UNSIGNED-INSTALL.txt" "$staging/UNSIGNED-INSTALL.txt"
ditto "$root/LICENSE" "$staging/LICENSE"
ln -s /Applications "$staging/Applications"

mkdir -p "$output_dir"
dmg="$output_dir/ChatGPTUsage-$version.dmg"
hdiutil create -volname "ChatGPT Usage" -srcfolder "$staging" -ov -format UDZO "$dmg"
hdiutil verify "$dmg"
(
  cd "$output_dir"
  shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256"
)

packages=("$output_dir"/ChatGPTUsage-<->.<->.<->.dmg(N))
if [[ "${KEEP_OLD_PACKAGES:-0}" != 1 ]] && (( ${#packages} > 3 )); then
  for package in "${packages[@]:0:${#packages}-3}"; do
    rm -f "$package"
    rm -f "$package.sha256"
    print "Removed old package $package"
  done
fi

print "Created $dmg"
print "Created $dmg.sha256"
