#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <Odysseus.ipa>" >&2
  exit 2
fi

ipa=$1
if [[ ! -f "$ipa" ]]; then
  echo "IPA not found: $ipa" >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/odysseus-ipa.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

ditto -x -k "$ipa" "$work_dir"
payload="$work_dir/Payload"
if [[ ! -d "$payload" ]]; then
  echo "IPA is missing Payload/" >&2
  exit 1
fi

apps=()
while IFS= read -r app_path; do
  apps+=("$app_path")
done < <(find "$payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print)
if [[ ${#apps[@]} -ne 1 ]]; then
  echo "Expected exactly one app bundle in Payload/, found ${#apps[@]}" >&2
  exit 1
fi

app=${apps[0]}
if [[ "$(basename "$app")" != "Odysseus.app" ]]; then
  echo "Unexpected app bundle name: $(basename "$app")" >&2
  exit 1
fi

info_plist="$app/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  echo "App bundle is missing Info.plist" >&2
  exit 1
fi
plutil -lint "$info_plist" >/dev/null

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

bundle_id=$(plist_value CFBundleIdentifier)
display_name=$(plist_value CFBundleDisplayName)
minimum_os=$(plist_value MinimumOSVersion)
executable=$(plist_value CFBundleExecutable)
short_version=$(plist_value CFBundleShortVersionString)

[[ "$bundle_id" == "com.mirazbakis.Odysseus" ]] || {
  echo "Unexpected bundle identifier: $bundle_id" >&2
  exit 1
}
[[ "$display_name" == "Odysseus" ]] || {
  echo "Unexpected display name: $display_name" >&2
  exit 1
}
[[ "$minimum_os" == "17.0" ]] || {
  echo "Unexpected minimum iOS version: $minimum_os (expected 17.0)" >&2
  exit 1
}
[[ -n "$short_version" ]] || {
  echo "CFBundleShortVersionString is empty" >&2
  exit 1
}
[[ -x "$app/$executable" ]] || {
  echo "App executable is missing or not executable: $executable" >&2
  exit 1
}

# The project intentionally emits an ad-hoc-signed IPA. Verify the final
# bundle after every resource-copy operation, not the pre-package app.
codesign --verify --deep --strict --verbose=2 "$app"
signature_details=$(codesign --display --verbose=4 "$app" 2>&1)
grep -q '^Signature=adhoc$' <<<"$signature_details" || {
  echo "Expected an ad-hoc code signature on the final app bundle" >&2
  exit 1
}

# This unsigned distribution has no provisioning profile by design. If one
# appears, parse it with Apple's CMS tooling and ensure it targets this app.
profile="$app/embedded.mobileprovision"
if [[ -f "$profile" ]]; then
  profile_plist="$work_dir/embedded-profile.plist"
  security cms -D -i "$profile" >"$profile_plist"
  plutil -lint "$profile_plist" >/dev/null
  profile_app_id=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")
  case "$profile_app_id" in
    *".$bundle_id") ;;
    *)
      echo "Provisioning profile application-identifier does not match $bundle_id" >&2
      exit 1
      ;;
  esac
else
  echo "No embedded provisioning profile (expected for the ad-hoc IPA)."
fi

# No signing identity, private key, or old shared local-server key belongs in
# this app bundle. Check both filenames and PEM payloads without printing them.
if find "$app" -type f \( \
  -iname '*.p12' -o -iname '*.pfx' -o -iname 'server.pem' -o \
  -iname '*private*key*' \
\) -print -quit | grep -q .; then
  echo "A private signing/server key file is bundled in the app" >&2
  exit 1
fi

while IFS= read -r -d '' key_file; do
  if LC_ALL=C grep -aEq -- '-----BEGIN (RSA |DSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----' "$key_file"; then
    echo "A PEM private key is bundled in the app" >&2
    exit 1
  fi
done < <(find "$app" -type f \( -iname '*.pem' -o -iname '*.key' -o -iname '*.txt' \) -print0)

echo "IPA verified: Payload structure, Odysseus identity/version/minimum OS, final ad-hoc signature, provisioning profile state, and no bundled private keys."
