---
id: MACPASS-1.1
title: Prove signed AutoFill extension discovery and Developer ID distribution
status: In Progress
assignee: []
created_date: '2026-08-11 20:03'
updated_date: '2026-08-11 22:30'
labels:
  - autofill
  - signing
  - spike
dependencies: []
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass.xcodeproj/project.pbxproj
  - MacPass.xcodeproj/xcshareddata/xcschemes/MacPass.xcscheme
  - MacPass/MacPass.entitlements
  - MacPass/MacPass-Developer-ID.entitlements
  - MacPassAutoFill/Info.plist
  - MacPassAutoFill/MacPassAutoFill.entitlements
  - MacPassAutoFill/CredentialProviderViewController.h
  - MacPassAutoFill/CredentialProviderViewController.m
  - MacPassAutoFillCore/MPAutoFillConstants.h
  - MacPassAutoFillCore/MPAutoFillConstants.m
  - MacPassAutoFillTests/MPAutoFillConstantsTests.m
parent_task_id: MACPASS-1
priority: high
type: spike
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Establish that the current nonsandboxed Developer ID MacPass host can embed, sign, notarize, install, and share state with a sandboxed AutoFill credential-provider extension before broader implementation proceeds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The host and extension have registered bundle identifiers and provisioning profiles authorizing AutoFill, the shared App Group, and the shared Keychain group
- [ ] #2 An archived Developer ID build is notarized, stapled, installed in Applications, and discovered by PlugInKit
- [ ] #3 The provider can be enabled in System Settings and the identity store reports enabled
- [ ] #4 Safari invokes the installed extension and can receive a hard-coded development credential
- [ ] #5 Minimum-supported and current macOS behavior is recorded, including any distribution blocker
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Local Slice 0 implementation is complete: the project contains an embedded macOS 11 credential-provider extension, shared App Group and Keychain entitlements, a development identity/configuration flow, noninteractive interaction-required behavior, and a non-hosted test target. Verified on Xcode 26.6: host and extension build successfully with ad-hoc signing; Xcode embedded-binary validation passes; strict deep codesign verification passes; extension metadata and macOS 11 minimum are correct; standalone extension builds arm64 and x86_64; extension links AuthenticationServices/Security/AppKit only and does not link KeePassKit or MacPassHTTP; 2 AutoFill tests and 30 healthy existing tests pass. Evidence: /var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillSlice0Tests.xcresult and /var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassHealthyTests.xcresult. Remaining acceptance needs registered App IDs/App Group, distinct provisioning profiles, Developer ID certificates/notarization credentials, /Applications install, PlugInKit/System Settings/Safari evidence, and a macOS 11 test environment.
<!-- SECTION:NOTES:END -->
