# macOS AutoFill Release Acceptance

This checklist records evidence that cannot be produced by entitlement-free CI.
Run it against the exact notarized release candidate installed in `/Applications`.

## Required Environment

- A Developer ID Application certificate.
- Separate Developer ID provisioning profiles for `dev.roszkowski.macpass` and
  `dev.roszkowski.macpass.autofill`.
- Both profiles authorize `group.dev.roszkowski.macpass`, the shared Keychain
  group, and the AutoFill credential-provider entitlement.
- Test systems for the minimum supported AutoFill release and the current macOS.
- Safari and one non-browser app with password AutoFill fields.

## Distribution Evidence

Record the release URL, commit, version, build number, macOS version, hardware,
and timestamps with every command result or screenshot.

1. Verify the downloaded DMG and installed application:

   ```sh
   shasum -a 256 MacPass-*.dmg
   xcrun stapler validate MacPass-*.dmg
   xcrun stapler validate /Applications/MacPass.app
   spctl --assess --type open --context context:primary-signature -vv MacPass-*.dmg
   spctl --assess --type exec -vv /Applications/MacPass.app
   codesign --verify --deep --strict --verbose=2 /Applications/MacPass.app
   codesign --verify --strict --verbose=2 /Applications/MacPass.app/Contents/PlugIns/MacPassAutoFill.appex
   ```

2. Capture signed entitlements for the host and extension. Verify exact bundle
   application identifiers, App Group, shared Keychain group, sandbox on the
   extension, and the credential-provider entitlement:

   ```sh
   codesign -d --entitlements :- /Applications/MacPass.app
   codesign -d --entitlements :- /Applications/MacPass.app/Contents/PlugIns/MacPassAutoFill.appex
   ```

3. Verify PlugInKit discovery and capture the output:

   ```sh
   pluginkit -m -A -D -i dev.roszkowski.macpass.autofill
   ```

4. Open System Settings from MacPass preferences, enable MacPass Password
   AutoFill, and capture the enabled provider state in both locations.

## Product Acceptance

Use two explicitly enabled databases with at least one colliding entry UUID.
Do not include real credentials in screenshots, recordings, or logs.

1. Publish both databases and verify identities are offered in Safari.
2. Quit MacPass and verify interactive fill succeeds after user presence.
3. Repeat in a non-browser AutoFill client while MacPass remains terminated.
4. Cancel user presence and verify no credential is returned.
5. Save a changed username/password and verify the old value is not offered.
6. Delete an entry and verify its identity is removed.
7. Change the database master key and verify the next publication succeeds.
8. Remove one publication and verify its identities disappear while the other
   database remains available.
9. Disable the provider and verify MacPass reports the disabled system state.
10. Re-enable, uninstall, reinstall, and record App Group and Keychain behavior.
11. Exercise direct and list requests repeatedly under extension termination or
    memory pressure and record latency, memory, and recovery behavior.

## Evidence Review

- Store command logs, screenshots, and recordings with the release record.
- Redact usernames, passwords, source paths, URLs, and Keychain item data.
- Link every result from `MACPASS-1.1`, `MACPASS-1.8`, `MACPASS-1.9`, and
  `MACPASS-1.11`.
- A failure or missing artifact keeps the corresponding criterion open.
