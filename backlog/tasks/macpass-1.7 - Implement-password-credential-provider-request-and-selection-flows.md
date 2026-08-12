---
id: MACPASS-1.7
title: Implement password credential-provider request and selection flows
status: Done
assignee: []
created_date: '2026-08-11 20:04'
labels:
  - autofill
  - extension
  - ui
dependencies:
  - MACPASS-1.3
  - MACPASS-1.4
  - MACPASS-1.6
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPassAutoFill/CredentialProviderViewController.m
  - MacPassAutoFill/MPAutoFillRequestCoordinator.h
  - MacPassAutoFill/MPAutoFillCredentialListViewController.h
  - MacPassAutoFillTests/MPAutoFillRequestCoordinatorTests.m
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the macOS credential-provider extension so direct suggestions and credential-list selection authenticate, decrypt, validate, and return password credentials without depending on the MacPass process.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 macOS 11-13 identity callbacks and macOS 14+ request callbacks are availability-gated and supported
- [x] #2 A noninteractive request either completes from authorized state or returns UserInteractionRequired without showing UI
- [x] #3 Interactive requests handle authorization success, cancellation, unavailable biometry, and login-password fallback
- [x] #4 The decrypted envelope, index digest, publication, generation, entry, and requested service are all validated before filling
- [x] #5 The full credential list is shown only after authentication and exact matches rank first
- [x] #6 The provider fills while MacPass is terminated and does not cache decrypted snapshots across requests in the MVP
<!-- AC:END -->

## Evidence

- `CredentialProviderViewController` implements the macOS 11-13 identity callbacks and availability-gated macOS 14 request callbacks. Non-password requests fail closed.
- Noninteractive private-key reads disable interaction and map `MPAutoFillErrorUserInteractionRequired` to `ASExtensionErrorCodeUserInteractionRequired` without presenting extension UI.
- Interactive reads use a fresh `LAContext` and the user-presence Keychain access control, which supports available biometric or login-password authentication. User cancellation maps to `ASExtensionErrorCodeUserCanceled`; unavailable or failed authentication fails closed.
- `MPAutoFillRequestCoordinator` strictly parses the record identifier, reads one authoritative generation, decrypts against its publication/generation/index digest, cross-checks index metadata, locates the entry UUID, and revalidates the requested service before returning a password.
- Credential-list requests authenticate and decrypt each enabled publication before constructing the list. Requested service identifiers are evaluated in order, exact matches rank before the remaining authenticated credentials, and no snapshot is retained after the method returns.
- The extension reads only App Group generations and shared Keychain state. It has no dependency on a running MacPass process.
- AutoFill test bundle: 42/42 passed, including noninteractive escalation, interactive exact-service rejection, and authenticated list ranking. The arm64 macOS 11 extension and macOS 10.14 host with embedded extension build successfully without code signing.
