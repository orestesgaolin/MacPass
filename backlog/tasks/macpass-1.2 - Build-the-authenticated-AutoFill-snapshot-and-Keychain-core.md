---
id: MACPASS-1.2
title: Build the authenticated AutoFill snapshot and Keychain core
status: In Progress
assignee: []
created_date: '2026-08-11 20:04'
updated_date: '2026-08-12 00:54'
labels:
  - autofill
  - security
  - keychain
dependencies:
  - MACPASS-1.1
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass.xcodeproj/project.pbxproj
  - MacPassAutoFillCore/MPAutoFillCredentialRecord.h
  - MacPassAutoFillCore/MPAutoFillCredentialRecord.m
  - MacPassAutoFillCore/MPAutoFillErrors.h
  - MacPassAutoFillCore/MPAutoFillErrors.m
  - MacPassAutoFillCore/MPAutoFillSnapshot.h
  - MacPassAutoFillCore/MPAutoFillSnapshot.m
  - MacPassAutoFillCore/MPAutoFillEnvelopeCrypto.h
  - MacPassAutoFillCore/MPAutoFillEnvelopeCrypto.m
  - MacPassAutoFillCore/MPAutoFillKeychainStore.h
  - MacPassAutoFillCore/MPAutoFillKeychainStore.m
  - MacPassAutoFillTests/MPAutoFillEnvelopeCryptoTests.m
  - MacPassAutoFillTests/MPAutoFillKeychainStoreTests.m
  - MacPassAutoFillTests/MPAutoFillSnapshotTests.m
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provide a shared app/extension core that serializes only AutoFill-eligible primitive records, encrypts and authenticates them with a per-publication Security.framework key pair, and authorizes secret decryption through the shared data-protection Keychain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The snapshot schema is versioned, strictly validated, and enforces field, record-count, and total-size limits
- [x] #2 The encrypted envelope binds publication ID, generation ID, schema version, and public-index digest
- [ ] #3 The app can encrypt without user interaction and the extension-side private-key operation requires user presence
- [ ] #4 All Keychain operations use the shared access group, data-protection Keychain, and ThisDeviceOnly accessibility
- [ ] #5 Tampered, truncated, wrong-key, unknown-version, and canceled-authentication cases fail closed
- [x] #6 No source KDBX or source composite key is persisted in the shared store
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented a bounded binary-property-list snapshot containing only primitive credential records and authenticated context metadata. The envelope uses Security.framework's RSA OAEP SHA-256 plus AES-GCM hybrid algorithm and fails closed for metadata mismatch, mutation, truncation, and wrong keys. The Keychain store scopes 3072-bit per-publication key pairs and current-generation records to the shared access group and data-protection Keychain with ThisDeviceOnly accessibility; private keys use user-presence and private-key-usage access controls. Security errors preserve only interaction-required, user-cancelled, and authentication-failed decisions; other decrypt failures remain generic.

Validation on Xcode 26.6: 16 AutoFill core tests pass with 0 failures. Evidence: `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillSecureCoreTests5.xcresult`. Isolated host and provider builds also pass at macOS 10.14 and macOS 11 deployment targets, respectively, under `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassSecureCoreHostBuild` and `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassSecureCoreExtensionBuild`.

Acceptance criteria 3-5 remain open pending a correctly provisioned host/provider pair. Ad-hoc unsigned tests cannot validate shared-access-group reads, actual user-presence prompts, cancellation behavior, key rotation/deletion, or enrollment-change behavior.
<!-- SECTION:NOTES:END -->
