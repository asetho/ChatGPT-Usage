#!/bin/zsh
set -euo pipefail
setopt numeric_glob_sort

root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$root/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 "VERSION must use semantic versioning (for example 1.0.1)."; exit 1; }

signing_identity="${DEVELOPER_ID_APPLICATION:-}"
notary_profile="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"
if [[ -n "$signing_identity" || -n "$notary_profile" ]]; then
  [[ -n "$signing_identity" && -n "$notary_profile" ]] || {
    print -u2 "Set both DEVELOPER_ID_APPLICATION and NOTARYTOOL_KEYCHAIN_PROFILE for a notarized build."
    exit 1
  }
  xcrun --find notarytool >/dev/null
  xcrun --find stapler >/dev/null
  notarize=1
else
  notarize=0
fi

output_dir="${OUTPUT_DIR:-$root/dist}"
dmg_name="ChatGPTUsage-$version.dmg"
final_dmg="$output_dir/$dmg_name"
final_checksum="$final_dmg.sha256"
[[ ! -e "$final_dmg" && ! -e "$final_checksum" ]] || {
  print -u2 "Package already exists: $final_dmg. Choose a new VERSION or OUTPUT_DIR."
  exit 1
}

pending_dir="$output_dir/.notarization-$version"
pending_dmg="$pending_dir/$dmg_name"
pending_id="$pending_dir/submission-id"
pending_sha="$pending_dir/sha256"
resume=0
if [[ -e "$pending_dir" ]]; then
  (( notarize )) && [[ -f "$pending_dmg" && -f "$pending_id" && -f "$pending_sha" ]] || {
    print -u2 "Incomplete notarization checkpoint at $pending_dir. Inspect it before rebuilding."
    exit 1
  }
  resume=1
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-usage-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

if (( ! resume )); then
dmgbuild_cmd="${commands[dmgbuild]:-}"
if [[ -z "$dmgbuild_cmd" ]]; then
  dmgbuild_venv="$root/build/dmgbuild-venv"
  if [[ ! -x "$dmgbuild_venv/bin/dmgbuild" ]]; then
    mkdir -p "$root/build"
    python3 -m venv "$dmgbuild_venv"
    "$dmgbuild_venv/bin/python" -m pip install --disable-pip-version-check 'dmgbuild==1.6.7'
  fi
  dmgbuild_cmd="$dmgbuild_venv/bin/dmgbuild"
fi
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

if (( notarize )); then
  ditto "$root/LICENSE" "$app/Contents/Resources/LICENSE"
  codesign --force --sign "$signing_identity" --options runtime --timestamp "$app"
  codesign -d --verbose=4 "$app" 2>&1 | grep '^Authority=Developer ID Application:' >/dev/null || {
    print -u2 "The app is not signed with a Developer ID Application certificate."
    exit 1
  }
else
  # Login Items requires a valid bundle signature; ad hoc signing does not verify a publisher.
  codesign --force --sign - --options runtime --timestamp=none "$app"
fi
codesign --verify --strict "$app"

staging="$build_dir/dmg-root"
mkdir -p "$staging"
ditto "$app" "$staging/ChatGPT Usage.app"
if (( ! notarize )); then
  ditto "$root/UNSIGNED-INSTALL.txt" "$staging/UNSIGNED-INSTALL.txt"
  ditto "$root/LICENSE" "$staging/LICENSE"
fi

dmg="$build_dir/$dmg_name"
background="$build_dir/dmg-background.png"
swift "$root/scripts/generate-dmg-background.swift" \
  "$root/CodexUsage/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png" "$background" "$notarize"
CHATGPT_USAGE_DMG_STAGING="$staging" \
CHATGPT_USAGE_DMG_BACKGROUND="$background" \
CHATGPT_USAGE_DMG_UNSIGNED="$(( ! notarize ))" \
  "$dmgbuild_cmd" -s "$root/scripts/dmg-settings.py" "ChatGPT Usage" "$dmg"
if (( notarize )); then
  mkdir -p "$pending_dir"
  mv "$dmg" "$pending_dmg"
  dmg="$pending_dmg"
  shasum -a 256 "$dmg" | awk '{print $1}' > "$pending_sha"
  response="$build_dir/notarization-submit.plist"
  xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --no-wait --output-format plist > "$response"
  submission_id="$(plutil -extract id raw -o - "$response")"
  print -r -- "$submission_id" > "$pending_id"
fi
else
  dmg="$pending_dmg"
  submission_id="$(tr -d '[:space:]' < "$pending_id")"
  if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
    [[ "$(shasum -a 256 "$dmg" | awk '{print $1}')" == "$(< "$pending_sha")" ]] || {
      print -u2 "The pending DMG changed after submission. Nothing was installed."
      exit 1
    }
  fi
  print "Resuming notarization submission $submission_id"
fi

if (( notarize )); then
  [[ "$submission_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || {
    print -u2 "Invalid notarization submission ID at $pending_id."
    exit 1
  }
  response="$build_dir/notarization-wait.plist"
  xcrun notarytool wait "$submission_id" --keychain-profile "$notary_profile" --timeout "${NOTARY_TIMEOUT:-30m}" --output-format plist > "$response" || true
  xcrun notarytool info "$submission_id" --keychain-profile "$notary_profile" --output-format plist > "$response"
  notary_status="$(plutil -extract status raw -o - "$response")"
  if [[ "$notary_status" != Accepted ]]; then
    print -u2 "Notarization $notary_status (submission $submission_id). Signed DMG retained at $pending_dmg."
    if [[ "$notary_status" == Invalid || "$notary_status" == Rejected ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" >&2 || true
    fi
    exit 1
  fi
  if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
    xcrun stapler staple "$dmg"
  fi
  xcrun stapler validate "$dmg"
fi
hdiutil verify "$dmg"
shasum -a 256 "$dmg" | awk -v name="$dmg_name" '{print $1 "  " name}' > "$build_dir/$dmg_name.sha256"

mkdir -p "$output_dir"
[[ ! -e "$final_dmg" && ! -e "$final_checksum" ]] || {
  print -u2 "Package appeared during the build: $final_dmg. Existing files were preserved."
  exit 1
}
mv "$dmg" "$final_dmg"
mv "$build_dir/$dmg_name.sha256" "$final_checksum"
if (( notarize )); then
  rm "$pending_id" "$pending_sha"
  rmdir "$pending_dir"
fi

packages=("$output_dir"/ChatGPTUsage-<->.<->.<->.dmg(N))
if [[ "${KEEP_OLD_PACKAGES:-0}" != 1 ]] && (( ${#packages} > 3 )); then
  for package in "${packages[@]:0:${#packages}-3}"; do
    rm -f "$package"
    rm -f "$package.sha256"
    print "Removed old package $package"
  done
fi

print "Created $final_dmg"
print "Created $final_checksum"
