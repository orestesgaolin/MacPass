---
id: MACPASS-1.6
title: Synchronize all published credentials with the macOS identity store
status: Done
assignee: []
created_date: '2026-08-11 20:04'
labels:
  - autofill
  - authenticationservices
  - sync
dependencies:
  - MACPASS-1.5
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass/AutoFill/MPAutoFillIdentityStoreUpdater.h
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Maintain ASCredentialIdentityStore as a coherent projection of every enabled AutoFill publication, including removal and recovery from expected store states.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Identity updates are assembled from all enabled publications and never erase unrelated vault identities
- [x] #2 A generation is active before its identities are published
- [x] #3 Deleted entries, disabled publications, and stale identities are removed or fail closed
- [x] #4 Disabled-store and incremental-unsupported states are handled without losing publication data
- [x] #5 Store Busy retries are bounded and final synchronization state is observable without exposing sensitive values
- [x] #6 Multiple publications with colliding source entry or root UUIDs remain distinct
<!-- AC:END -->

## Evidence

- `MPAutoFillIdentityStoreUpdater` queries `ASCredentialIdentityStoreState`, assembles a complete replacement from every registry publication's active generation, and never writes a single-document subset.
- Publication synchronization is triggered only after `MPAutoFillGenerationStore` activates the generation. Key-first revocation clears the active pointer before identity replacement.
- Complete replacement removes deleted entries and disabled publications. Registry publications with no active pointer are omitted during key-first removal, while corrupt active generations fail synchronization.
- Disabled stores are an observable expected state and do not modify registry or generation data. Complete replacement is used whether or not incremental updates are supported.
- Store Busy retries stop after three attempts. Public state exposes only status, count, attempt count, and error category; it does not expose credential values.
- Stable `v1:<publicationUUID>:<entryUUID>` identifiers keep colliding entry/root UUIDs distinct across publications.
- Focused updater tests: 5/5 passed, covering multi-publication collisions, disabled state, bounded retries, publication removal, and revoked publications without active generations.
