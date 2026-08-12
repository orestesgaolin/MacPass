#!/usr/bin/env python3

import copy
import datetime
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROFILE_VALIDATOR = ROOT / "scripts" / "validate_autofill_profile.py"
ENTITLEMENT_VALIDATOR = ROOT / "scripts" / "validate_autofill_signed_entitlements.py"
TEAM = "TEAM123456"
PREFIX = TEAM + "."
HOST_BUNDLE_ID = "dev.roszkowski.macpass"
EXTENSION_BUNDLE_ID = HOST_BUNDLE_ID + ".autofill"
APP_GROUP = "group.dev.roszkowski.macpass"
HOST_IDENTIFIER = PREFIX + HOST_BUNDLE_ID
EXTENSION_IDENTIFIER = PREFIX + EXTENSION_BUNDLE_ID
SHARED_KEYCHAIN_GROUP = PREFIX + "dev.roszkowski.macpass.shared"
CERTIFICATE = b"authorized-certificate"


class AutoFillReleaseValidatorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.certificate_path = self.root / "certificate.der"
        self.certificate_path.write_bytes(CERTIFICATE)

    def tearDown(self):
        self.directory.cleanup()

    def write_plist(self, name, value):
        path = self.root / name
        with path.open("wb") as stream:
            plistlib.dump(value, stream)
        return path

    def profile(self, bundle_id=HOST_BUNDLE_ID, keychain_groups=None, sandboxed=False):
        identifier = PREFIX + bundle_id
        entitlements = {
            "com.apple.application-identifier": identifier,
            "com.apple.developer.authentication-services.autofill-credential-provider": True,
            "com.apple.security.application-groups": [APP_GROUP],
            "keychain-access-groups": keychain_groups or [identifier, SHARED_KEYCHAIN_GROUP],
        }
        if sandboxed:
            entitlements["com.apple.security.app-sandbox"] = True
        return {
            "TeamIdentifier": [TEAM],
            "ApplicationIdentifierPrefix": [PREFIX],
            "ExpirationDate": datetime.datetime.now(datetime.UTC).replace(tzinfo=None)
            + datetime.timedelta(days=1),
            "Platform": ["OSX"],
            "ProvisionsAllDevices": True,
            "DeveloperCertificates": [CERTIFICATE],
            "Entitlements": entitlements,
        }

    def run_profile(self, profile, bundle_id=HOST_BUNDLE_ID, groups=None, sandboxed=False):
        path = self.write_plist("profile.plist", profile)
        command = [
            "python3", str(PROFILE_VALIDATOR), str(path), TEAM, bundle_id, APP_GROUP,
            PREFIX, str(self.certificate_path),
        ]
        if sandboxed:
            command.append("--sandboxed")
        command.extend(groups or [HOST_IDENTIFIER, SHARED_KEYCHAIN_GROUP])
        return subprocess.run(command, capture_output=True, text=True)

    def test_profiles_accept_exact_and_wildcard_keychain_grants(self):
        self.assertEqual(self.run_profile(self.profile()).returncode, 0)
        no_dot_prefix = self.profile()
        no_dot_prefix["ApplicationIdentifierPrefix"] = [TEAM]
        self.assertEqual(
            self.run_profile(no_dot_prefix, groups=[HOST_IDENTIFIER, SHARED_KEYCHAIN_GROUP]).returncode,
            0,
        )
        prefixed_app_group = self.profile()
        prefixed_app_group["Entitlements"]["com.apple.security.application-groups"] = [
            PREFIX + APP_GROUP
        ]
        self.assertEqual(self.run_profile(prefixed_app_group).returncode, 0)
        wildcard_app_group = self.profile()
        wildcard_app_group["Entitlements"]["com.apple.security.application-groups"] = [
            PREFIX + "*"
        ]
        self.assertEqual(self.run_profile(wildcard_app_group).returncode, 0)
        wildcard = self.profile(keychain_groups=[PREFIX + "*"])
        self.assertEqual(self.run_profile(wildcard).returncode, 0)
        wildcard_identifier = self.profile()
        wildcard_identifier["Entitlements"]["com.apple.application-identifier"] = PREFIX + "*"
        self.assertEqual(self.run_profile(wildcard_identifier).returncode, 0)
        extension = self.profile(
            EXTENSION_BUNDLE_ID, [SHARED_KEYCHAIN_GROUP], sandboxed=True
        )
        self.assertEqual(
            self.run_profile(
                extension, EXTENSION_BUNDLE_ID, [SHARED_KEYCHAIN_GROUP], sandboxed=True
            ).returncode,
            0,
        )

    def test_profile_rejects_expiration_prefix_certificate_and_grants(self):
        mutations = []
        expired = self.profile()
        expired["ExpirationDate"] = datetime.datetime.now(datetime.UTC).replace(tzinfo=None)
        mutations.append(expired)
        wrong_prefix = self.profile()
        wrong_prefix["ApplicationIdentifierPrefix"] = ["OTHER12345."]
        mutations.append(wrong_prefix)
        wrong_certificate = self.profile()
        wrong_certificate["DeveloperCertificates"] = [b"other-certificate"]
        mutations.append(wrong_certificate)
        wrong_group = self.profile(keychain_groups=["OTHER.*"])
        mutations.append(wrong_group)
        wrong_app_group = self.profile()
        wrong_app_group["Entitlements"]["com.apple.security.application-groups"] = [
            PREFIX + "group.other"
        ]
        mutations.append(wrong_app_group)
        for profile in mutations:
            with self.subTest(profile=profile):
                self.assertEqual(self.run_profile(profile).returncode, 1)

    def test_extension_profile_requires_sandbox(self):
        profile = self.profile(EXTENSION_BUNDLE_ID, [SHARED_KEYCHAIN_GROUP])
        result = self.run_profile(
            profile, EXTENSION_BUNDLE_ID, [SHARED_KEYCHAIN_GROUP], sandboxed=True
        )
        self.assertEqual(result.returncode, 1)

    def signed_entitlements(self):
        host = {
            "com.apple.application-identifier": HOST_IDENTIFIER,
            "com.apple.developer.team-identifier": TEAM,
            "com.apple.developer.authentication-services.autofill-credential-provider": True,
            "com.apple.security.application-groups": [APP_GROUP],
            "keychain-access-groups": [HOST_IDENTIFIER, SHARED_KEYCHAIN_GROUP],
        }
        extension = {
            "com.apple.application-identifier": EXTENSION_IDENTIFIER,
            "com.apple.developer.team-identifier": TEAM,
            "com.apple.developer.authentication-services.autofill-credential-provider": True,
            "com.apple.security.app-sandbox": True,
            "com.apple.security.application-groups": [APP_GROUP],
            "keychain-access-groups": [SHARED_KEYCHAIN_GROUP],
        }
        return host, extension

    def run_entitlements(self, host, extension):
        host_path = self.write_plist("host.plist", host)
        extension_path = self.write_plist("extension.plist", extension)
        return subprocess.run(
            [
                "python3", str(ENTITLEMENT_VALIDATOR), str(host_path),
                str(extension_path), TEAM, PREFIX,
            ],
            capture_output=True,
            text=True,
        )

    def test_signed_entitlements_accept_expected_values(self):
        self.assertEqual(self.run_entitlements(*self.signed_entitlements()).returncode, 0)
        host, extension = self.signed_entitlements()
        host_path = self.write_plist("host.plist", host)
        extension_path = self.write_plist("extension.plist", extension)
        result = subprocess.run(
            [
                "python3", str(ENTITLEMENT_VALIDATOR), str(host_path),
                str(extension_path), TEAM, TEAM,
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)

    def test_signed_entitlements_reject_each_security_boundary(self):
        host, extension = self.signed_entitlements()
        mutations = [
            ("host", "com.apple.application-identifier", "OTHER.host"),
            ("host", "com.apple.developer.team-identifier", "OTHERTEAM"),
            ("host", "com.apple.developer.authentication-services.autofill-credential-provider", False),
            ("host", "com.apple.security.application-groups", ["group.other"]),
            ("host", "keychain-access-groups", [HOST_IDENTIFIER]),
            ("extension", "com.apple.application-identifier", "OTHER.extension"),
            ("extension", "com.apple.developer.team-identifier", "OTHERTEAM"),
            ("extension", "com.apple.developer.authentication-services.autofill-credential-provider", False),
            ("extension", "com.apple.security.app-sandbox", False),
            ("extension", "com.apple.security.application-groups", ["group.other"]),
            ("extension", "keychain-access-groups", ["OTHER.shared"]),
        ]
        for target, key, value in mutations:
            with self.subTest(target=target, key=key):
                changed_host = copy.deepcopy(host)
                changed_extension = copy.deepcopy(extension)
                selected = changed_host if target == "host" else changed_extension
                selected[key] = value
                self.assertEqual(
                    self.run_entitlements(changed_host, changed_extension).returncode, 1
                )


if __name__ == "__main__":
    unittest.main()
