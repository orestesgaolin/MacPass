---
id: MACPASS-1.3
title: 'Define credential identity, eligibility, and exact service matching'
status: Done
assignee: []
created_date: '2026-08-11 20:04'
updated_date: '2026-08-12 08:27'
labels:
  - autofill
  - matching
  - security
dependencies:
  - MACPASS-1.2
references:
  - docs/macos-autofill-credential-provider-plan.md
modified_files:
  - MacPass.xcodeproj/project.pbxproj
  - MacPassAutoFillCore/MPAutoFillCredentialIdentifier.h
  - MacPassAutoFillCore/MPAutoFillCredentialIdentifier.m
  - MacPassAutoFillCore/MPAutoFillServiceMatcher.h
  - MacPassAutoFillCore/MPAutoFillServiceMatcher.m
  - MacPass/AutoFill/MPAutoFillSnapshotBuilder.h
  - MacPass/AutoFill/MPAutoFillSnapshotBuilder.m
  - MacPassAutoFillTests/MPAutoFillCredentialIdentifierTests.m
  - MacPassAutoFillTests/MPAutoFillServiceMatcherTests.m
  - MacPassTests/MPTestAutoFillSnapshotBuilder.m
parent_task_id: MACPASS-1
priority: high
type: feature
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create stable local credential identifiers and deterministic publication-time eligibility and service matching rules shared by identity publication and extension request revalidation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Record identifiers encode and strictly parse a versioned publication UUID plus entry UUID
- [x] #2 Exact-host matching correctly distinguishes domain and URL service identifiers
- [x] #3 Tests cover schemes, host case, trailing dots, default and explicit ports, IDNs, IPv4, IPv6, malformed URLs, and host-suffix attacks
- [x] #4 History, trash, templates, meta entries, expired entries, malformed URLs, and empty passwords are excluded according to documented policy
- [x] #5 Deterministic references are resolved in the app and interactive or dynamic placeholders are rejected with a reportable eligibility reason
- [x] #6 The extension can revalidate a requested service against the decrypted credential rather than trusting only its record identifier
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented strict `v1:<publicationUUID>:<entryUUID>` identity encoding/parsing and a shared native AutoFill matcher. Domain requests compare exact normalized hosts. URL requests use the selected exact-origin policy: normalized HTTP/HTTPS scheme, exact normalized host, and effective port. Paths, queries, and fragments do not affect matching. Matching fails closed for relative or malformed URLs, credentials in authorities, invalid ports, repeated trailing dots, and host-suffix attacks.

The app-side builder emits bounded primitive records and non-sensitive exclusion reason codes. It excludes history, trash, templates, meta entries, expired entries, empty passwords, malformed URLs, invalid records, and unsupported placeholders. Only UUID-based deterministic references are resolved. The complete reference graph is checked for cycles, structurally excluded targets, unresolved references, and dynamic/interactive placeholders introduced by referenced values.

Validation on Xcode 26.6: 23 non-hosted AutoFill tests pass with 0 failures at `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS13AutoFillTests2.xcresult`; 5 hosted builder tests pass with 0 failures at `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassSnapshotBuilderTests3.xcresult`. Isolated host and provider builds pass under `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS13HostBuild` and `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassMACPASS13ExtensionBuild`.

The extension request coordinator loads the authoritative generation, decrypts and validates the selected record, and calls the shared matcher against the requested AuthenticationServices service identifier. Coordinator tests reject host-suffix attacks and accept only the documented exact service policy.
<!-- SECTION:NOTES:END -->
