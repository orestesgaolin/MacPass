---
id: MACPASS-1
title: Ship MacPass as a macOS AutoFill credential provider
status: To Do
assignee: []
created_date: '2026-08-11 20:02'
updated_date: '2026-08-11 20:41'
labels:
  - autofill
  - macos
  - security
dependencies: []
references:
  - docs/macos-autofill-credential-provider-plan.md
priority: high
type: feature
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deliver the password-provider MVP defined in docs/macos-autofill-credential-provider-plan.md: MacPass is discoverable by macOS, publishes explicitly enabled credentials through a minimal authenticated device-local snapshot, and fills in Safari and another AutoFill client while the main app is not running. MacPassHTTP is outside this feature and is neither used nor modified.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A signed installed MacPass build can be enabled as a credential provider in macOS
- [ ] #2 Eligible credentials from multiple explicitly enabled databases are offered and filled after user-presence authorization
- [ ] #3 The provider works while MacPass is not running and does not depend on MacPassHTTP
- [ ] #4 Saves, deletions, password changes, stale state, and unpublish synchronize or fail closed
- [ ] #5 No plaintext password or source database composite key is persisted or logged
- [ ] #6 The complete validation matrix and MVP definition in the referenced plan are satisfied
<!-- AC:END -->
