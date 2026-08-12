---
id: MACPASS-1.4
title: Implement transactional AutoFill generation storage and recovery
status: Done
assignee: []
created_date: '2026-08-11 20:04'
updated_date: '2026-08-12 08:47'
labels:
  - autofill
  - storage
  - reliability
dependencies:
  - MACPASS-1.2
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass.xcodeproj/project.pbxproj
  - MacPassAutoFillCore/MPAutoFillErrors.h
  - MacPassAutoFillCore/MPAutoFillKeychainStore.h
  - MacPassAutoFillCore/MPAutoFillGenerationStore.h
  - MacPassAutoFillCore/MPAutoFillGenerationStore.m
  - MacPassAutoFillCore/MPAutoFillVaultIndex.h
  - MacPassAutoFillCore/MPAutoFillVaultIndex.m
  - MacPassAutoFillTests/MPAutoFillGenerationStoreTests.m
  - MacPassAutoFillTests/MPAutoFillVaultIndexTests.m
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Publish immutable index and encrypted-secret generations to the App Group without allowing the extension to observe mixed, partial, or rolled-back state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Index and secret files from one immutable generation are built and validated before that generation becomes current
- [x] #2 The authoritative current generation changes atomically only after all generation files are durable
- [x] #3 The previous valid generation remains available until publication succeeds
- [x] #4 Interrupted publication at every write and activation point recovers to a valid generation or no usable generation
- [x] #5 Concurrent readers never combine files from different generations
- [x] #6 Unpublish revokes the private key before identities and files are removed, and orphan cleanup is bounded and tested
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented a strict minimal binary-plist vault index with no password field and an immutable generation store rooted in the App Group. Index bytes are validated before publication and SHA-256 hashed exactly as stored. The encrypted snapshot binds that digest through the existing envelope contract.

Generation directories and files use descriptor-relative `openat` operations, `O_NOFOLLOW`, exclusive creation, owner/type/link checks, and restrictive `0700`/`0600` modes. Each file and newly created parent entry is fully synchronized before the injected shared-Keychain pointer is updated. Readers load the pointer once and read both files from only that generation; corrupt or missing current state fails closed without fallback. Publication and cleanup are serialized per store instance. Bounded descriptor-relative cleanup protects the current, explicitly retained previous, and in-flight generations.

Validation on Xcode 26.6: 34 non-hosted AutoFill tests pass with 0 failures at `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS14AutoFillTests.xcresult`. Tests cover activation failure, previous-generation retention, corrupt-current no-fallback, swapped indexes, symlink substitution, unsafe permissions, bounded cleanup, and concurrent readers observing only complete old or new generations. Isolated host and extension builds pass under `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS14HostBuild` and `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS14ExtensionBuild`.

Unpublish now invalidates queued saves, revokes the private key, clears the active pointer, waits for identity replacement, and only then removes bounded generation storage and registry metadata. Generation-removal tests verify complete deletion and idempotency. Stale-save ordering remains implemented by MACPASS-1.5's per-publication sequencing; generation UUIDs are not treated as ordered values.
<!-- SECTION:NOTES:END -->
