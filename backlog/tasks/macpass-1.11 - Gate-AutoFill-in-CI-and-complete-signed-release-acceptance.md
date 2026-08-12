---
id: MACPASS-1.11
title: Gate AutoFill in CI and complete signed release acceptance
status: To Do
assignee: []
created_date: '2026-08-11 20:04'
updated_date: '2026-08-11 20:41'
labels:
  - autofill
  - ci
  - release
dependencies:
  - MACPASS-1.9
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - docs/macos-autofill-release-acceptance.md
  - docs/macos-autofill-validation-matrix.md
  - scripts/validate_autofill_profile.py
  - scripts/validate_autofill_product.sh
  - scripts/validate_autofill_signed_entitlements.py
  - scripts/test_autofill_release_validators.py
parent_task_id: MACPASS-1
priority: high
type: task
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make the complete password-provider feature continuously buildable and close it with installed signed-product evidence, while distinguishing entitlement-free CI checks from real provisioning and notarization proof.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI builds the host, embedded extension, shared core, and all AutoFill test targets without regressing the healthy MacPass suite
- [ ] #2 Core, storage, matching, publication, identity, and extension coordinator tests run in CI
- [x] #3 The release checklist records archive signing, nested code verification, notarization, stapling, installation, PlugInKit discovery, and System Settings enablement
- [ ] #4 Installed Safari and non-browser fill acceptance passes while MacPass is not running
- [ ] #5 No logs or generated artifacts contain plaintext passwords, source composite keys, sensitive URLs, or source file paths
- [x] #6 Every acceptance criterion and validation section in docs/macos-autofill-credential-provider-plan.md is linked to current evidence or an explicitly documented environmental limitation
<!-- AC:END -->

## Evidence

- CI builds the `MacPass` scheme, which embeds `MacPassAutoFill.appex`, and runs the complete host and non-hosted AutoFill test targets through the shared scheme. It now writes and uploads `MacPass-CI.xcresult` for each run.
- CI scans the built application and result bundle for distinctive AutoFill fixture credentials, URLs, database names, and key-file names. Findings fail the job and report only containing artifact paths, not matched secret content.
- The release workflow now requires separate host and AutoFill extension Developer ID provisioning-profile secrets. It validates exact application identifiers, the shared App Group, shared Keychain group, and credential-provider entitlement before embedding either profile.
- Release signing now signs `MacPassAutoFill.appex` before the outer application with its sandbox and shared-access entitlements, then verifies both nested signatures and exact signed application identifiers before notarization.
- The release workflow now asserts `arm64` and `x86_64` slices on all five input frameworks and on the final host and extension executables. It also validates exact host/extension bundle IDs, the extension's macOS 11 minimum, and the credential-provider extension-point identifier before signing.
- Embedded frameworks are now signed without inheriting host application entitlements. App Group, shared Keychain, credential-provider, Apple Events, and library-validation exceptions remain scoped to the host or AutoFill extension that requires them.
- `docs/macos-autofill-release-acceptance.md` defines the installed-product evidence procedure for nested signatures, entitlements, notarization, stapling, PlugInKit discovery, System Settings, Safari, a non-browser client, MacPass-terminated filling, lifecycle changes, reinstall, and termination pressure.
- Local workflow syntax validation passes for `.github/workflows/ci.yml` and `.github/workflows/release.yml`; `git diff --check` passes. The updated CI and release jobs have not yet run in GitHub, and signed installed-product criteria remain open until the required profiles, certificates, notarization credentials, systems, and clients are available.
- The sensitive-marker gate was executed locally against the latest built application (excluding the embedded XCTest bundle, which intentionally contains fixtures) and the 133-test result bundle; both scans completed with no findings.
- An isolated unsigned Release build of target `MacPassAutoFill` succeeds as a universal `arm64 x86_64` extension with macOS 11 deployment. Evidence: `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/macpass-autofill-universal-extension-target/products/Release/MacPassAutoFill.appex`. The complete local universal host build cannot link because the checked-out local Carthage frameworks are arm64-only; the release workflow rebuilds them universally and now verifies every slice before linking.
- `docs/macos-autofill-validation-matrix.md` maps every required plan validation area and MVP condition to current local evidence, partial evidence, or a specific installed-environment limitation. It distinguishes code/process independence from unproven signed end-to-end behavior.
- Host and extension plist templates now use `MARKETING_VERSION` for `CFBundleShortVersionString`, while the release workflow uses the numeric GitHub run number for `CURRENT_PROJECT_VERSION` and stamps both bundles identically. This removes the embedded-binary validation mismatch and invalid prerelease extension build versions caused by using a semantic tag as `CFBundleVersion`.
- `scripts/validate_autofill_product.sh` is shared by CI and release. It explicitly fails for invalid bundle IDs, nonnumeric versions, missing architecture slices, invalid provider metadata, version mismatches, and KeePassKit/MacPassHTTP extension links. A prior prerelease-stamped product was confirmed rejected before the numeric Release product passed.
- `scripts/validate_autofill_profile.py` performs explicit, optimization-safe validation of profile team, prefix, expiration, platform, Developer ID distribution mode, certificate authorization, application identifier, exact App Group and Keychain groups, provider capability, and extension sandboxing. Synthetic valid, expired, wrong-prefix, and wrong-certificate cases produced the expected accept/reject results.
- A fresh realistic unsigned Release arm64 product with numeric version `0.9.0` passes Xcode embedded-binary validation, the reusable product preflight, and the sensitive-marker scan. Evidence: `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/macpass-autofill-release-preflight-3/Build/Products/Release/MacPass.app`.
- The exact CI-style build-then-test sequence passed 137/137 tests: 69 healthy host tests and 68 AutoFill core/extension tests. The fresh result bundle and product both pass the sensitive-marker scan. Evidence: `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillDeliveryFinalTests.xcresult`.
- Release signing imports the complete PKCS#12 aggregate and verifies that the configured Developer ID Application identity has a usable private key before building. Profile validation accepts exact or wildcard Keychain grants while rejecting unauthorized groups.
- Final validation mounts the notarized DMG and rechecks the exact packaged application: universal slices, bundle metadata, embedded profiles, nested signatures, Gatekeeper assessment, stapled tickets, complete host/extension entitlements, and sensitive fixture markers.
- Prerelease tags create GitHub prereleases and are excluded from the stable Sparkle appcast. Appcast text is XML-escaped and the generated document must pass `xmllint`.
- The fork's `production` environment contains the distinct host/extension provisioning profiles, Developer ID identity, and notarization credentials required by the workflow. The workflow now references that exact environment name. Secret contents and signed behavior remain unverified until the workflow runs from committed code.
- CI runs `scripts/test_autofill_release_validators.py` before dependency builds. Its five test methods cover 20 subprocess-level paths: exact/wildcard host grants, sandboxed extension grants, expiration, prefix, certificate and unauthorized-group rejection, plus acceptance of exact final entitlements and rejection of every host/extension security boundary.
