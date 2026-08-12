---
id: MACPASS-1.5
title: Publish AutoFill generations from exact successful document saves
status: Done
assignee: []
created_date: '2026-08-11 20:04'
labels:
  - autofill
  - document
  - lifecycle
dependencies:
  - MACPASS-1.3
  - MACPASS-1.4
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass/MPDocument.m
  - MacPass/AutoFill/MPAutoFillCoordinator.h
  - MacPass/AutoFill/MPAutoFillPublicationRegistry.h
  - MacPass/AutoFill/MPAutoFillPublicationSequencer.h
  - MacPass/AutoFill/MPAutoFillSavePolicy.h
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Connect the MacPass document lifecycle to AutoFill publication so every active generation represents an exact successfully saved database revision and publication work never changes document-save success.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Publication uses the exact successfully saved revision rather than a later mutable document tree
- [x] #2 Ordinary save, autosave, Save As, Save To, failed save, lock-triggered save, revert, and external replacement follow explicit tested rules
- [x] #3 Password-only, key-file-only, and combined-key changes publish only after a successful save
- [x] #4 Per-publication serialization prevents an older save from replacing a newer published generation
- [x] #5 Publication failure is surfaced separately and does not fail or deadlock the document save or lock callback
- [x] #6 KDB and supported KDBX source formats can publish without modifying their metadata
<!-- AC:END -->

## Evidence

- `MPDocument` captures the save-specific composite key, reads the completed destination before invoking the AppKit completion callback, ignores failed saves and Save To, and sends publication work asynchronously.
- `MPAutoFillCoordinator` reconstructs a detached `KPKTree` from those encrypted bytes, builds one index/snapshot pair, encrypts it, and activates it through `MPAutoFillGenerationStore`.
- `MPAutoFillPublicationSequencer` serializes activation with successful-save token registration. `MPAutoFillSavePolicy` gives successful normal/autosave/lock saves, Save As, Save To, failed saves, and disabled publications explicit outcomes.
- Save As prompts to move the existing publication or create a separately keyed publication, after the document save has already completed successfully.
- Revert and external replacement revoke the private key first, clear the active pointer, verify the replacement root UUID from exact replacement bytes, and republish only when the previous key opens the same database.
- `xcodebuild test ... -only-testing:MacPassTests/MPTestAutoFillCoordinator -only-testing:MacPassAutoFillTests`: 5/5 lifecycle sequencing/policy tests and 34/34 core tests passed on arm64.
- `xcodebuild ... -target MacPass ... ARCHS=arm64`: host build and embedded extension validation succeeded.
