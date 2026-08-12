#!/bin/bash

set -euo pipefail

app="${1:?Usage: validate_autofill_product.sh /path/to/MacPass.app [architectures]}"
required_architectures="${2:-}"
app_plist="$app/Contents/Info.plist"
app_binary="$app/Contents/MacOS/MacPass"
extension="$app/Contents/PlugIns/MacPassAutoFill.appex"
extension_plist="$extension/Contents/Info.plist"
extension_binary="$extension/Contents/MacOS/MacPassAutoFill"

for path in "$app_plist" "$app_binary" "$extension_plist" "$extension_binary"; do
  test -e "$path"
done

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

test "$(plist_value "$app_plist" CFBundleIdentifier)" = "dev.roszkowski.macpass"
test "$(plist_value "$extension_plist" CFBundleIdentifier)" = "dev.roszkowski.macpass.autofill"
test "$(plist_value "$extension_plist" LSMinimumSystemVersion)" = "11.0"
test "$(plist_value "$extension_plist" NSExtension:NSExtensionPointIdentifier)" = \
  "com.apple.authentication-services-credential-provider-ui"
if plist_value "$extension_plist" \
    NSExtension:NSExtensionAttributes:ASCredentialProviderExtensionShowsConfigurationUI >/dev/null 2>&1; then
  echo "The AutoFill extension must not advertise host-managed configuration UI." >&2
  exit 1
fi

app_version="$(plist_value "$app_plist" CFBundleShortVersionString)"
app_build="$(plist_value "$app_plist" CFBundleVersion)"
test "$app_version" = "$(plist_value "$extension_plist" CFBundleShortVersionString)"
test "$app_build" = "$(plist_value "$extension_plist" CFBundleVersion)"
if [[ ! "$app_version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "The bundle marketing version is not numeric: $app_version" >&2
  exit 1
fi
if [[ ! "$app_build" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "The bundle build version is not numeric: $app_build" >&2
  exit 1
fi

if [[ -n "$required_architectures" ]]; then
  for binary in "$app_binary" "$extension_binary"; do
    architectures=" $(lipo -archs "$binary") "
    for architecture in $required_architectures; do
      if [[ "$architectures" != *" $architecture "* ]]; then
        echo "Missing $architecture architecture in $binary" >&2
        exit 1
      fi
    done
  done
fi

dependencies="$(otool -L "$extension_binary")"
if [[ "$dependencies" == *"KeePassKit"* || "$dependencies" == *"MacPassHTTP"* ]]; then
  echo "The AutoFill extension links a forbidden dependency." >&2
  exit 1
fi

echo "AutoFill product preflight passed: $app_version ($app_build)"
