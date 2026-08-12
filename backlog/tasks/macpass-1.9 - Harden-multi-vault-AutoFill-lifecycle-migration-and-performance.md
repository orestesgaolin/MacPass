---
id: MACPASS-1.9
title: 'Harden multi-vault AutoFill lifecycle, migration, and performance'
status: In Progress
assignee: []
created_date: '2026-08-11 20:04'
labels:
  - autofill
  - security
  - reliability
dependencies:
  - MACPASS-1.8
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass/MPDocument.m
  - MacPass/AutoFill/MPAutoFillCoordinator.h
  - MacPass/AutoFill/MPAutoFillCoordinator.m
  - MacPassAutoFill/MPAutoFillRequestCoordinator.m
  - MacPassAutoFillCore/MPAutoFillGenerationStore.h
  - MacPassAutoFillCore/MPAutoFillGenerationStore.m
  - MacPassAutoFillCore/MPAutoFillKeychainStore.h
  - MacPassAutoFillCore/MPAutoFillKeychainStore.m
  - MacPassAutoFillTests/MPAutoFillGenerationStoreTests.m
  - MacPassAutoFillTests/MPAutoFillKeychainStoreTests.m
  - MacPassAutoFillTests/MPAutoFillRequestCoordinatorTests.m
  - MacPassTests/MPTestDocument.m
  - MacPassTests/MPTestAutoFillSnapshotBuilder.m
  - MacPassTests/Databases/AutoFillFixtures.md
parent_task_id: MACPASS-1
priority: high
type: enhancement
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Close the lifecycle, scale, tamper-resistance, and compatibility matrix required for the password-provider MVP across real database and operating-system conditions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Multiple published databases, UUID collisions, rename, move, Save As, duplicate, replacement, read-only source, and external-change behavior pass
- [x] #2 Forged, truncated, rolled-back, symlinked, permission-weakened, stale, and missing shared state fails closed
- [ ] #3 Large-vault publication and extension requests meet recorded latency and memory budgets under extension termination pressure
- [x] #4 Upgrade, schema migration, unsupported-newer-schema, downgrade, disable, uninstall, reinstall, and orphan cleanup behavior is tested and documented
- [x] #5 KDB and KDBX 3.1, 4, and 4.1 sources plus password, key-file, and combined credentials are covered
- [ ] #6 Safari and at least one non-browser AutoFill client pass installed-product acceptance
<!-- AC:END -->

## Evidence

- External replacement now uses the complete fail-closed unpublish path when the replacement cannot be reconstructed as the same database or its new key pair cannot be created. The registry identifier remains available until identities and generation data have been removed, avoiding orphaned publication data.
- Save As now has an explicit Cancel action; dismissed and unexpected modal responses do not create a separate publication.
- Save As detaches the document from its original publication before presenting Move, Separate, or Cancel. Only a successfully completed Move or Separate action rebinds it, so cancellation and setup failures cannot publish later saves under stale source metadata.
- Registry lifecycle tests now verify persistence across registry reloads, filesystem rename, explicit publication move, copied databases with colliding root UUIDs requiring separate enablement, multiple file-scoped publications with colliding root UUIDs, and registration of a `0444` source without changing its bytes or modification date.
- Credential-list reconciliation uses an entry-identifier map instead of an O(n^2) nested scan and rejects duplicate or extra index records.
- Multi-vault request coverage verifies that colliding entry UUIDs remain separate across publication UUIDs.
- Registry reads are descriptor-relative, bounded, and no-follow. They reject unsafe root/file permissions, symlinks, hard links, invalid ownership/type, truncation, malformed schemas, and duplicate publication UUIDs. The host disables registry mutation if existing state cannot be validated instead of replacing it as empty.
- Generation activation now stores matching versioned activation and high-water records in the device-only shared Keychain. The high-water record is written first; mismatches, missing modern markers, and restored older activation records fail closed. UUID-only v1 records remain readable only while no high-water marker exists and migrate on the next successful publication.
- Request-boundary tests now exercise malformed and stale identities, missing pointers and generation directories, tampered encrypted secrets, truncated and permission-weakened registries, duplicate registry publications, and a corrupt vault in a multi-vault list. Every case returns no credentials.
- Registry membership is now required for direct requests as well as complete lists. Missing registry state or a removed publication fails stale direct identities closed even when Keychain and generation data survive.
- Host and extension registry readers now require exact known keys, canonical UUIDs, integral numeric schema values, and typed records. Unsupported future registry state is preserved and cannot be overwritten by an older host. Vault-index old/new schema rejection and forged same-generation index metadata are tested at direct and list request boundaries.
- Application startup now performs complete identity reconciliation followed by bounded best-effort orphan generation cleanup for every independently valid registry publication. Corrupt or missing active state is preserved and reported, while healthy publications still receive cleanup. Injected coordinator dependencies provide deterministic recovery and identity-failure coverage.
- Startup now descriptor-safely enumerates canonical App Group publication directories and compares them with an authoritative registry. It revokes at most 32 storage orphans per launch in key-pair, activation/high-water, then generation-file order. Missing registries are authoritative empty state after reinstall; malformed, unsafe, or unsupported-future registries disable destructive cleanup and preserve all state.
- Cold-start recovery coverage recreates the registry and coordinator over persisted state, retains and cleans a valid publication, and fully revokes an App Group orphan. Generation-store enumeration rejects noncanonical, symlinked, unsafe, or excessive publication storage rather than partially trusting it.
- Startup now enumerates exact versioned AutoFill private/public key tags and activation/high-water services using attribute-only, interaction-disabled Keychain queries. Keychain-only orphans surviving App Group loss are included in the same bounded revocation flow; unrelated key tags are ignored, while malformed namespaced state or enumeration failure prevents all destructive cleanup.
- Publication preparation and registry registration now execute as one coordinator transaction on the reconciliation queue. Startup cleanup cannot observe and revoke a newly created key before its registry record exists, and failed registration deletes partial key and activation state. Keychain discovery accepts duplicate rows at the 1,024-unique-publication limit and rejects a 1,025th unique UUID.
- Unpublish is tested as an idempotent retryable sequence across private/public key deletion, activation/high-water deletion, identity replacement, generation deletion, and registry deletion. Each injected first-attempt failure prevents later cleanup stages; the registry remains as the retry handle and the second attempt completes. Repeated successful unpublish is also harmless.
- Real encrypted KDBX replacement coverage verifies the revert/Use Other security boundary. A replacement with the expected root UUID revokes the old key and activation, recreates the key pair, retains the publication, and republishes exact replacement bytes. Root mismatch, malformed encrypted data, and key-recreation failure all execute complete unpublish and leave no registry publication.
- External-change strategy coverage verifies that Merge changes only in-memory document state until a later successful save, Keep Mine does not invoke merge or revert, and Use Other routes exclusively through the AutoFill-aware revert path. Unreadable replacement files now fail `readFromURL:` instead of reporting a successful revert that could spuriously revoke AutoFill state.
- A cold-coordinator test publishes the schema maximum of 5,000 records and enforces conservative Debug budgets of 5 seconds for direct requests, 15 seconds for complete-list requests, and 128 MiB physical-footprint growth. On Apple silicon with macOS 26.5 SDK/XCTest, the recorded full-suite run completed direct lookup in 0.053 seconds, list assembly in 0.101 seconds, and grew physical footprint by 31.6 MiB.
- Bundled fixtures exercise KDB and KDBX 3.1, 4, and 4.1 with password-only, key-file-only, and combined credentials. All eight encrypted source/credential cases decrypt and reach the AutoFill snapshot builder; four incomplete or incorrect credential combinations fail before the builder.
- Local validation passes 68/68 AutoFill core tests and 43/43 host AutoFill/document integration tests. The added eligibility cases cover empty usernames, exact expiration boundaries, historical-secret omission, meta entries, and reference cycles; identity replacement now directly covers entry deletion. Evidence: `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillDeliveryFinalTests.xcresult`.
- Remaining acceptance work is installed-runtime evidence: signed uninstall/reinstall behavior against the real shared Keychain/App Group, extension termination-pressure measurements, and signed Safari/non-browser client acceptance.
