#!/usr/bin/env python3

import argparse
import datetime
import plistlib
import sys


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


parser = argparse.ArgumentParser()
parser.add_argument("profile")
parser.add_argument("team")
parser.add_argument("bundle_id")
parser.add_argument("app_group")
parser.add_argument("prefix")
parser.add_argument("certificate")
parser.add_argument("keychain_groups", nargs="+")
parser.add_argument("--sandboxed", action="store_true")
args = parser.parse_args()

with open(args.profile, "rb") as stream:
    profile = plistlib.load(stream)
with open(args.certificate, "rb") as stream:
    certificate = stream.read()

entitlements = profile.get("Entitlements", {})
identifier_prefix = args.prefix.rstrip(".") + "."
expected_identifier = identifier_prefix + args.bundle_id
actual_keychain_groups = entitlements.get("keychain-access-groups", [])
profile_prefixes = profile.get("ApplicationIdentifierPrefix", [])


def authorizes_keychain_group(grant, group):
    if grant == group:
        return True
    return grant.endswith("*") and group.startswith(grant[:-1])


def authorizes_identifier(grant, identifier):
    if grant == identifier:
        return True
    return grant.endswith("*") and identifier.startswith(grant[:-1])


checks = (
    (profile.get("TeamIdentifier") == [args.team], "profile team mismatch"),
    (len(profile_prefixes) == 1 and profile_prefixes[0].rstrip(".") == args.prefix.rstrip("."), "profile prefix mismatch"),
    (profile.get("ExpirationDate", datetime.datetime.min) > datetime.datetime.now(datetime.UTC).replace(tzinfo=None), "profile expired"),
    ("OSX" in profile.get("Platform", []), "profile does not support macOS"),
    (profile.get("ProvisionsAllDevices") is True, "profile is not Developer ID distribution"),
    (not profile.get("ProvisionedDevices"), "development profile is not allowed"),
    (certificate in profile.get("DeveloperCertificates", []), "signing certificate is not authorized"),
    (authorizes_identifier(entitlements.get("com.apple.application-identifier", ""), expected_identifier), "application identifier mismatch"),
    (entitlements.get("com.apple.developer.authentication-services.autofill-credential-provider") is True, "AutoFill entitlement missing"),
    (entitlements.get("com.apple.security.application-groups") == [args.app_group], "App Group mismatch"),
    (all(any(authorizes_keychain_group(grant, group) for grant in actual_keychain_groups) for group in args.keychain_groups), "Keychain group is not authorized"),
)
for valid, message in checks:
    if not valid:
        fail(message)

if args.sandboxed and entitlements.get("com.apple.security.app-sandbox") is not True:
    fail("extension sandbox entitlement missing")

print(f"Provisioning profile passed: {args.bundle_id}")
