#!/usr/bin/env python3

import argparse
import plistlib
import sys


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load(path):
    with open(path, "rb") as stream:
        return plistlib.load(stream)


parser = argparse.ArgumentParser()
parser.add_argument("host_entitlements")
parser.add_argument("extension_entitlements")
parser.add_argument("team")
parser.add_argument("prefix")
args = parser.parse_args()

host_identifier = args.prefix + "dev.roszkowski.macpass"
extension_identifier = host_identifier + ".autofill"
shared_keychain_group = args.prefix + "dev.roszkowski.macpass.shared"
app_group = "group.dev.roszkowski.macpass"

host = load(args.host_entitlements)
extension = load(args.extension_entitlements)
checks = (
    (host.get("com.apple.application-identifier") == host_identifier, "host application identifier mismatch"),
    (host.get("com.apple.developer.team-identifier") == args.team, "host team identifier mismatch"),
    (host.get("com.apple.developer.authentication-services.autofill-credential-provider") is True, "host AutoFill entitlement missing"),
    (host.get("com.apple.security.application-groups") == [app_group], "host App Group mismatch"),
    (host.get("keychain-access-groups") == [host_identifier, shared_keychain_group], "host Keychain groups mismatch"),
    (extension.get("com.apple.application-identifier") == extension_identifier, "extension application identifier mismatch"),
    (extension.get("com.apple.developer.team-identifier") == args.team, "extension team identifier mismatch"),
    (extension.get("com.apple.developer.authentication-services.autofill-credential-provider") is True, "extension AutoFill entitlement missing"),
    (extension.get("com.apple.security.app-sandbox") is True, "extension sandbox entitlement missing"),
    (extension.get("com.apple.security.application-groups") == [app_group], "extension App Group mismatch"),
    (extension.get("keychain-access-groups") == [shared_keychain_group], "extension Keychain groups mismatch"),
)
for valid, message in checks:
    if not valid:
        fail(message)

print("Signed AutoFill entitlements passed")
