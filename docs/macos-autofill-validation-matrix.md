# macOS AutoFill Validation Matrix

This document maps the required validation in
`docs/macos-autofill-credential-provider-plan.md` to current evidence. `Local`
means entitlement-free build or test evidence. `Installed` requires the exact
signed and notarized release candidate and cannot be inferred from local tests.

## Build And Distribution

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Unsigned/ad-hoc CI compilation | Local pass | `MacPass` host and embedded extension build with signing disabled. The CI workflow builds the host first and runs the complete scheme. |
| Properly signed Development build | Installed required | Requires registered App IDs, App Group, shared Keychain group, and separate profiles. Procedure: `docs/macos-autofill-release-acceptance.md`. |
| Developer ID archive, notarization, staple, installation, discovery | Installed required | Release workflow validates profiles, signs nested code, notarizes, and staples. It has not run with the required AutoFill extension profile. |
| Minimum and current supported macOS | Partial | Host deployment is macOS 10.14; provider deployment is macOS 11. Installed provider behavior still requires macOS 11 and current-macOS systems. |
| Nested runpaths and signatures | Partial | Universal extension links system frameworks only. Signed nested-code verification remains installed acceptance. |

## Publication And Recovery

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Crash points around activation | Local pass | Transactional immutable generation tests cover failed activation, old/new readers, stale saves, and activation/high-water rollback. |
| Concurrent publication, read, and unpublish | Local pass | Generation readers observe complete old or new state; save sequencing and retryable ordered unpublish are covered. Installed process termination remains external. |
| Truncated, forged, rolled-back, symlinked, weak-permission state | Local pass | Core and request-boundary tests fail closed for each class. |
| Orphan cleanup | Local pass | Startup covers App Group-only and Keychain-only orphans, malformed discovery, bounded cleanup, and retry behavior. |
| Older publication cannot overwrite newer save | Local pass | Publication sequencer tests reject superseded save tokens. |

## Database Lifecycle

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| KDB and KDBX 3.1, 4, 4.1 | Local pass | Eight encrypted source fixtures reach snapshot construction. |
| Password, key-file, combined credentials | Local pass | Correct combinations succeed; four wrong or incomplete combinations fail before publication. |
| Password/key-file changes | Local pass | Replacement revokes old key and activation before reconstruction; failure fully unpublishes. Real shared-Keychain behavior remains installed acceptance. |
| Save, autosave, Save As, Save To | Local pass | Save policy and registry binding tests cover publication, no-publication, Move, Separate, and Cancel. |
| Duplicate, rename, move, replacement, revert | Local pass | File-scoped registry reload, colliding roots, replacement, and revert tests pass. |
| External file change | Local pass | Merge waits for a successful save, Keep Mine does nothing, and Use Other routes through replacement. |
| Read-only source | Local pass | `0444` source registration preserves bytes and modification time. |

## Credential Eligibility

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Deleted, trash, history, template, expired, meta | Local pass | Snapshot-builder exclusions and identity replacement tests cover noneligible records and deletion. |
| Empty password and username | Local pass | Empty passwords are excluded; empty usernames remain valid password credentials. |
| References and interactive placeholders | Local pass | Valid UUID references resolve; references to excluded records and dynamic placeholders fail eligibility. |
| Malformed, Unicode, IPv4, IPv6 URLs | Local pass | Exact-origin/host matcher tests cover malformed values, IDN, IPv4, bracketed IPv6, ports, and suffix attacks. |
| Multiple vault UUID collisions | Local pass | Publication-qualified identifiers keep colliding entry and root UUIDs separate. |

## Extension And Keychain

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Direct request with UI prohibited | Local pass | Noninteractive requests use interaction-disabled `LAContext` and return UserInteractionRequired. |
| Interactive success and cancellation | Partial | Error mapping and request completion are tested. Actual user-presence success/cancel requires signed shared-Keychain access. |
| Login-password fallback and unavailable biometry | Installed required | Provided by user-presence access control; must be exercised on installed systems. |
| Locked Keychain and enrollment change | Installed required | Requires real login Keychain and biometric state. |
| Invalid/stale ID, missing generation, tampered envelope | Local pass | Direct and list request-boundary tests fail closed. |
| Large-vault latency and termination pressure | Partial | 5,000-record Debug budgets pass. Real extension termination and memory pressure require an installed provider. |

## Identity Store

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Disabled and enabled states | Partial | Disabled-state behavior and UI rendering are tested. Enabled state requires System Settings. |
| Store Busy retry exhaustion | Local pass | Retry is bounded to three attempts. |
| Complete multi-publication replacement | Local pass | Tests cover multiple publications and colliding entries. |
| Incremental unsupported | Local pass | Implementation performs complete replacement only. |
| Entry deletion and publication removal | Local pass | Replacement omits deleted entries and removed publications. |
| Activation/identity interruption | Local pass | Startup reconciliation reconstructs identities from authoritative registry and active generations. |

## Upgrade And Cleanup

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Upgrade from build without AutoFill | Local pass | Missing registry is authoritative empty state and startup remains valid. |
| Schema migration and unsupported newer schema | Local pass | Legacy activation migration is bounded; unknown snapshot/index/registry schemas fail closed and future registry data is preserved. |
| Downgrade | Local pass | Older readers reject newer schemas and cannot overwrite unsupported registry state. |
| Disable | Partial | Provider-disabled UI and identity behavior are tested; System Settings behavior is installed acceptance. |
| Uninstall, reinstall, App Group/Keychain orphans | Partial | Cold-instance simulations cover persisted, App Group-only, and Keychain-only state. Actual platform container/Keychain retention requires signed installation. |

## Password Provider MVP

| Requirement | Status | Evidence or limitation |
| --- | --- | --- |
| Enabled installed provider | Installed required | `MACPASS-1.1`, `MACPASS-1.8`. |
| Explicit eligible publication | Local pass | `MACPASS-1.3`, `MACPASS-1.5`, `MACPASS-1.8`. |
| Safari and non-browser identity offering | Installed required | `MACPASS-1.9`, `MACPASS-1.11`. |
| User-presence fill while MacPass is terminated | Installed required | Extension is process-independent locally; end-to-end authorization/fill requires installed acceptance. |
| Save, deletion, key change, unpublish synchronization | Local pass | `MACPASS-1.5`, `MACPASS-1.6`, `MACPASS-1.9`. |
| Multiple databases without collisions | Local pass | `MACPASS-1.3`, `MACPASS-1.6`, `MACPASS-1.9`. |
| Stale/corrupt/tampered state fails closed | Local pass | `MACPASS-1.2`, `MACPASS-1.4`, `MACPASS-1.7`, `MACPASS-1.9`. |
| No plaintext password or source key persistence/logging | Partial | Schemas and artifact scans pass locally. Signed release logs/artifacts require final review. |

## Current Evidence

- Core and extension tests: 68/68 passed.
- Healthy host suite, including 43 AutoFill/document integration tests: 69/69 passed.
- Result bundle:
  `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillDeliveryFinalTests.xcresult` (137/137 total).
- Realistic unsigned Release arm64 product:
  `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/macpass-autofill-release-preflight-3/Build/Products/Release/MacPass.app`.
- Universal extension:
  `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/macpass-autofill-universal-extension-target/products/Release/MacPassAutoFill.appex`.
- Installed acceptance procedure:
  `docs/macos-autofill-release-acceptance.md`.
- Localized extension product:
  `/var/folders/qk/_hv81wwx33jd1zpl4g9f_38m0000gn/T/opencode/MacPassAutoFillLocalizedExtension/products/Debug/MacPassAutoFill.appex`.
- Eligibility coverage includes empty usernames, exact expiration boundaries,
  historical-secret omission, meta entries, direct/multi-hop reference cycles,
  and complete identity replacement after entry deletion.
