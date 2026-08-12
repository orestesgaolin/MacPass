---
id: MACPASS-1.8
title: 'Add AutoFill enablement, status, and unpublish settings'
status: In Progress
assignee: []
created_date: '2026-08-11 20:04'
labels:
  - autofill
  - settings
  - ux
dependencies:
  - MACPASS-1.5
  - MACPASS-1.6
  - MACPASS-1.7
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass/MPIntegrationPreferencesController.m
  - MacPass/Base.lproj/IntegrationPreferences.xib
  - MacPass/MPSettingsHelper.m
parent_task_id: MACPASS-1
priority: medium
type: feature
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Give users an explicit and understandable way to enable the current unlocked database for AutoFill, inspect publication health, enable the provider in macOS, and revoke published data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Enablement requires an unlocked successfully saved database and explicit confirmation
- [x] #2 The confirmation explains sensitive metadata exposure and that AutoFill remains separately available after MacPass locks or quits
- [x] #3 Preferences show provider state, published databases, last successful publication, and actionable synchronization errors
- [ ] #4 Enable-provider actions are availability-gated and older macOS versions show tested instructions or fallback behavior
- [x] #5 Unpublish revokes authorization and removes identities and shared data in fail-closed order
- [x] #6 Maintained localizations and accessibility labels cover the new controls and states
<!-- AC:END -->

## Evidence

- The Integration preferences pane enables publication only for the current unlocked, unmodified, file-backed database. It requires an explicit confirmation before creating keys, registry state, and a generation from the current saved bytes.
- Confirmation text identifies the exposed non-secret metadata, encrypted password storage, user-presence requirement, and availability after MacPass locks or quits.
- Preferences query identity-store state, list publication filenames and durable last-success dates, show synchronized identity counts, and provide actionable failure text without displaying credentials or source paths.
- Unpublish invalidates queued saves, revokes the private key, removes the active pointer, waits for complete identity replacement, then removes bounded generation storage and registry metadata. Cleanup failure leaves authorization revoked and reports a retryable state.
- AutoFill tests pass 44/44. New coverage verifies complete generation removal and that synchronization completion occurs only after identity replacement.
- The host and embedded macOS 11 extension build successfully for arm64 with the macOS 10.14 host deployment target.
- All 22 new visible/state strings are present in the 14 maintained localizations. `plutil -lint MacPass/*.lproj/Localizable.strings` passes. A hosted AppKit rendering test verifies unambiguous layout and non-empty accessibility labels for the publication selector and actions, and retains a PNG of the real Integration preferences view.
- The provider configuration and credential-list UI use an extension-owned Base localization table instead of hard-coded visible strings. The credential table has an explicit accessibility label. A fresh arm64 extension build embeds `Contents/Resources/Base.lproj/Localizable.strings` at `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillLocalizedExtension/products/Debug/MacPassAutoFill.appex`.
- Remaining: installed verification of the macOS 11-13 System Settings fallback.
