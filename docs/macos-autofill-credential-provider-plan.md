# macOS AutoFill Credential Provider Plan

Implementation is in progress. This document remains the architecture and
acceptance contract until signed installed-product validation is complete.

Status: implementation in progress; signed installed-product acceptance remains.

Last reviewed: 2026-08-11.

## Objective

Make MacPass discoverable as a macOS AutoFill credential provider so Safari and
other AutoFill clients can offer credentials stored in MacPass.

The first release is password-only. Passkeys, one-time codes, password capture,
and browser-native messaging are follow-up work and must not block the initial
provider.

MacPassHTTP is outside this plan. The native provider must neither use nor
modify it. The existing plugin may continue to ship unchanged, but its
migration, removal, and browser capture/update behavior are separate projects.

## Architecture

```text
MacPass.app
  MPDocument / KeePassKit
       |
       | successful save and explicit AutoFill publication
       v
App Group
  minimal public identity index
  authenticated encrypted credential generations
       |
       | shared data-protection Keychain authorization
       v
MacPassAutoFill.appex
  AuthenticationServices credential provider
```

The extension must work when MacPass is not running. It must not call a
localhost service or depend on an unlocked `MPDocument`.

## Security decisions

### Publish a minimal derived credential snapshot

Do not copy the source KDBX into the App Group and do not persist or share its
real `KPKCompositeKey`.

Sharing the source database key would grant the extension access to notes,
history, attachments, custom fields, TOTP seeds, and entries that are not
eligible for AutoFill. It would also couple persisted security data to
KeePassKit's Objective-C archive format.

Instead, publish only these fields for eligible entries:

- Local publication UUID.
- Entry UUID.
- Title needed for selection UI.
- Username.
- Password.
- Normalized service identifiers.
- Ranking/modification metadata.

The serialized secret snapshot is a strict, versioned property list containing
only property-list primitives. It is authenticated and encrypted with
Security.framework using `kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM`.
Security.framework documents this hybrid algorithm as supporting
arbitrary-length input.

The app encrypts with a public key without prompting. The extension decrypts
with a private key protected by user presence. KeePassKit is therefore not
required in the extension.

### Treat metadata as sensitive

Usernames, domains, entry titles, and vault names are sensitive metadata even
though they are not passwords. The public index must contain only what is
needed for identity lookup, use restrictive filesystem permissions, and be
authenticated by a digest stored inside the encrypted secret envelope.

The complete credential list should be shown only after authentication. Apple
may retain the username and service identifier placed in
`ASCredentialIdentityStore`; that exposure is inherent to participating in
system AutoFill and must be disclosed during enablement.

### AutoFill has a separate lock boundary

For the first release, an enabled AutoFill publication remains available after
the source MacPass document is locked or MacPass quits. Every interactive fill
requires its own user-presence authorization.

The enablement UI must state this explicitly. MacPass's Lock command clears the
app's decrypted document but does not claim to revoke an already running
extension process.

The first implementation does not cache decrypted credentials across extension
requests. A later optional policy to lock AutoFill with MacPass would need to
revoke the publication's private key and republish after a subsequent manual
unlock; a notification or generation counter alone is not guaranteed
revocation.

## Target and entitlement spike

This is Slice 0 because signing and installed extension discovery are the
highest-risk unknowns.

Update `MacPass.xcodeproj/project.pbxproj` to add:

- `MacPassAutoFill`, an application-extension target with macOS 11 minimum.
- `MacPassAutoFillTests`, a non-hosted XCTest target.
- AuthenticationServices and Security to the extension.
- An Embed App Extensions build phase in `MacPass`.
- The extension and its tests to the shared MacPass scheme.

Keep the app deployment target at macOS 10.14 initially. Shared source must
compile for that deployment target, and AuthenticationServices code must remain
in availability-gated app/extension adapters.

Create:

```text
MacPassAutoFill/
  Info.plist
  MacPassAutoFill.entitlements
  CredentialProviderViewController.h
  CredentialProviderViewController.m
  Base.lproj/CredentialProviderView.xib
```

The extension plist needs:

```text
NSExtension
  NSExtensionPointIdentifier =
    com.apple.authentication-services-credential-provider-ui
  NSExtensionPrincipalClass
  NSExtensionAttributes
    ASCredentialProviderExtensionShowsConfigurationUI = YES
```

Both `MacPass/MacPass.entitlements` and
`MacPassAutoFill/MacPassAutoFill.entitlements` need:

- `com.apple.developer.authentication-services.autofill-credential-provider`.
- A matching App Group.
- A matching shared Keychain access group.

Candidate identifiers:

```text
App Group:       group.dev.roszkowski.macpass
Keychain group:  $(AppIdentifierPrefix)dev.roszkowski.macpass.shared
Extension ID:    dev.roszkowski.macpass.autofill
```

The extension must have `com.apple.security.app-sandbox`. The host can remain
nonsandboxed, subject to a signed installation proving that its provisioned
App Group works with the sandboxed extension.

Slice 0 acceptance requires:

- Registered host and extension App IDs.
- Separate matching Developer ID provisioning profiles.
- Successful nested-code signing.
- Archive, notarization, stapling, and installation into `/Applications`.
- PlugInKit discovery of the extension.
- Provider visible and enabled in System Settings.
- `ASCredentialIdentityStore` reports enabled.
- A hard-coded development credential can be requested from Safari.
- Proof on the minimum supported macOS and the current macOS.

The existing CI deliberately clears entitlements. CI can prove compilation but
cannot close this signed-runtime gate.

## Module map

### Shared app and extension source

Create `MacPassAutoFillCore/` and add its sources to both targets rather than
introducing another dynamic framework initially.

```text
MacPassAutoFillCore/
  MPAutoFillConstants.h/.m
  MPAutoFillCredentialIdentifier.h/.m
  MPAutoFillCredentialRecord.h/.m
  MPAutoFillSnapshot.h/.m
  MPAutoFillVaultIndex.h/.m
  MPAutoFillEnvelopeCrypto.h/.m
  MPAutoFillKeychainStore.h/.m
  MPAutoFillGenerationStore.h/.m
  MPAutoFillServiceMatcher.h/.m
```

Responsibilities:

- `MPAutoFillCredentialIdentifier`
  - Encode `v1:<publicationUUID>:<entryUUID>`.
  - Strictly reject malformed and unknown versions.
- `MPAutoFillCredentialRecord`
  - Represent the validated primitive record schema.
- `MPAutoFillSnapshot`
  - Serialize and validate the versioned secret property list.
  - Enforce field, count, and total-size limits.
- `MPAutoFillVaultIndex`
  - Hold the minimal identity metadata and generation identifier.
- `MPAutoFillEnvelopeCrypto`
  - Encrypt with the publication public key.
  - Decrypt only through an authorized private-key operation.
  - Bind publication UUID, generation UUID, schema version, and index digest.
- `MPAutoFillKeychainStore`
  - Manage one key pair per publication.
  - Use the data-protection Keychain consistently.
- `MPAutoFillGenerationStore`
  - Publish and read immutable generations.
  - Recover from interrupted publication and clean orphans.
- `MPAutoFillServiceMatcher`
  - Normalize and compare domain and URL service identifiers.

### App-only source

Create:

```text
MacPass/AutoFill/
  MPAutoFillCoordinator.h/.m
  MPAutoFillSnapshotBuilder.h/.m
  MPAutoFillPublicationRegistry.h/.m
  MPAutoFillIdentityStoreUpdater.h/.m
  MPAutoFillSettingsModel.h/.m
```

- `MPAutoFillCoordinator` owns enable, publish, unpublish, and coalescing.
- `MPAutoFillSnapshotBuilder` converts a saved `KPKTree` into eligible,
  literal credential records.
- `MPAutoFillPublicationRegistry` maps source documents to local publication
  UUIDs without modifying the source database.
- `MPAutoFillIdentityStoreUpdater` owns all
  `ASCredentialIdentityStore` operations.
- `MPAutoFillSettingsModel` exposes provider/publication state to preferences.

### Extension-only source

Create:

```text
MacPassAutoFill/
  CredentialProviderViewController.h/.m
  MPAutoFillRequestCoordinator.h/.m
  MPAutoFillCredentialListViewController.h/.m
  Base.lproj/CredentialProviderView.xib
```

The request coordinator parses identifiers, loads the selected generation,
performs authentication, decrypts and validates the snapshot, revalidates the
service identifier, and completes or cancels the AuthenticationServices
request.

## Publication identity

Do not add an AutoFill UUID to KDB/KDBX metadata by default. Modifying metadata
can alter format requirements, would make enabling AutoFill change user data,
and would cause cloned databases to carry the same identifier.

Generate a local `publicationUUID` and associate it with:

- A persistent file bookmark or filesystem resource identifier.
- The database root UUID as secondary evidence.
- The current `MPDocument` instance while it is open.

Required behavior:

- Rename/move of the same filesystem object retains the publication.
- Save As asks whether the new file replaces or becomes a separate publication.
- Save To/export does not publish the exported copy.
- A duplicate must be separately enabled.
- Replacing a file at the same path requires root-UUID verification.
- Read-only KDB and KDBX databases can be published without modifying them.

## Transactional generation storage

Use this App Group layout:

```text
AutoFill/
  registry.plist
  Vaults/
    <publicationUUID>/
      generations/
        <generationUUID>/
          index.plist
          secrets.bin
```

The generation is immutable. Build both files from the same tree snapshot.
Write and validate the generation completely before making it current.

Store the authoritative current generation UUID in a small atomic shared
Keychain item. Updating this item after the files are durable prevents a
partially written generation from becoming visible. Only then update system
identities.

Keep the previous generation until publication and identity synchronization
succeed. A stale system identity must fail closed if its entry no longer exists
in the current generation.

Unpublishing order is:

1. Delete/revoke the publication private key.
2. Remove system identities.
3. Remove generation files and registry metadata.

This ensures a partial unpublish does not leave usable secret material.
Every deletion is idempotent. If any step fails, later steps do not run and the
registry record remains as a retry handle. A retry starts again with key
revocation and can safely complete from any previous partial state.

Registry membership, the current-generation Keychain state, the generation
files, and the private key are all required authorization inputs. Direct and
list requests fail closed if any input is missing or invalid. In particular, a
stale system identity cannot use Keychain and generation data after its registry
record has been removed.

## Compatibility and reinstall contract

All persisted property lists use strict binary schemas. Readers require exact
known keys and integral numeric schema values. Snapshot, public index, and
registry schema 1 are current. Unknown older or newer schemas fail closed and
are never rewritten by an incompatible host. Credential identifiers use `v1`;
unknown identifier versions fail closed.

Keychain activation schema 2 stores matching activation and high-water records.
The legacy UUID-only activation format remains readable only when no high-water
record exists. A successful publication replaces that legacy state with schema
2. A mismatch, interrupted migration, or unsupported activation schema fails
closed.

Upgrade from a build without AutoFill starts with no publications and does not
modify existing databases. Downgrade is non-destructive: unsupported state is
preserved but cannot be listed, filled, or changed. Disabling the provider keeps
published state so re-enabling can perform a complete identity replacement.
Uninstall and reinstall do not imply authorization recovery: surviving state is
usable only when all authorization inputs above remain valid. Missing App Group
or Keychain state fails closed. Application startup and opening Integration
preferences perform a complete identity reconciliation. After the startup
identity attempt, a bounded best-effort cleanup removes obsolete generations
from each independently valid publication. Invalid publication state is
preserved for diagnosis and retry and cannot prevent cleanup of healthy
publications. Generation cleanup protects the active and in-flight generations.

## Keychain contract

`MPAutoFillKeychainStore` must use:

- `kSecUseDataProtectionKeychain: @YES` for add, read, update, and delete.
- The shared access group on every query.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `kSecAccessControlUserPresence` on the private key.
- A separately persisted public key that can be read without interaction.
- Explicit interactive `LAContext` handling.
- Interaction-disabled reads for noninteractive AutoFill callbacks.

Cover cancellation, unavailable biometry, login-password fallback, locked login
Keychain, biometric enrollment changes, key rotation, migration, and deletion.
User presence must not be described as Touch ID-only.

## Building a credential snapshot

`MPAutoFillSnapshotBuilder` starts from the exact successfully saved database
revision and:

- Enumerates all entries.
- Excludes history, trash, templates, and meta entries.
- Excludes expired entries by default.
- Requires a valid service identifier and nonempty password.
- Supports an empty username only if AuthenticationServices accepts the desired
  identity behavior in the signed spike.
- Resolves deterministic KeePass references in the app.
- Rejects interactive or dynamic placeholders such as PICKCHAR and PICKFIELD.
- Emits literal username/password values so the extension does not evaluate
  KeePass expressions.
- Supports only the standard URL field in the MVP.

The settings UI should report entries excluded due to unsupported placeholders
or malformed URLs without logging their sensitive values.

## Save integration

Add a narrow hook to `MacPass/MPDocument.m` by overriding
`saveToURL:ofType:forSaveOperation:completionHandler:` and invoking `super`.

For an enabled publication after successful save:

1. Capture the key associated with that save in memory.
2. Re-read and decrypt the exact saved bytes in the app.
3. Build the derived generation from that reconstructed tree.
4. Enqueue publication on a per-publication serial coordinator.
5. Drop the result if a newer successful save already has a generation token.

Publication failure is reported separately and must not change document-save
success or block the existing lock-after-save callback.

Explicitly handle:

- Ordinary save.
- Autosave in place.
- Save As.
- Ignore Save To/export.
- Failed save.
- Lock-triggered save.
- Password/key-file change followed by failed or successful save.
- Revert and external file replacement.
- Concurrent/coalesced saves.

## Identity-store synchronization

`MPAutoFillIdentityStoreUpdater` must:

- Query store state before writing.
- Create `ASPasswordCredentialIdentity` values with stable record identifiers.
- Assemble the complete identity set from every enabled publication.
- Never replace the store using only the document that was just saved.
- Publish files/current generation before publishing identities.
- Initially use complete replacement for correctness.
- Add incremental add/update/remove after the basic path is proven.
- Retry Store Busy errors with a bounded policy.
- Remove stale identities after unpublish or entry deletion.
- Treat the identity store being disabled as expected state, not data loss.

## Credential-provider request behavior

Support both API generations:

- macOS 11-13 identity-based callbacks.
- macOS 14 and later request-based callbacks.

Direct request flow:

1. Strictly parse the record identifier.
2. Load the authoritative current generation.
3. Attempt an interaction-disabled private-key operation.
4. If interaction is required, cancel with
   `ASExtensionErrorCodeUserInteractionRequired`.
5. In the interactive callback, authorize user presence.
6. Decrypt and validate the secret envelope.
7. Verify its index digest and generation/publication UUIDs.
8. Locate the entry UUID.
9. Revalidate the requested service against the credential.
10. Return `ASPasswordCredential` or fail closed.
11. Release all secret objects and do not cache the snapshot for the MVP.

Credential-list flow authenticates before displaying the full list, filters
against the ordered service identifiers, and ranks exact matches first.

`ASSettingsHelper` APIs are availability-gated. The public request-to-enable API
is not available across the whole macOS 11 baseline; older systems get tested
instructions or a separately verified settings-opening fallback.

## Service matching

The MVP uses exact-host matching implemented specifically for native AutoFill.

`MPAutoFillServiceMatcher` must distinguish domain and URL service identifiers
and cover:

- Scheme normalization.
- Host case and trailing dots.
- Default and explicit ports.
- IDNs.
- IPv4 and bracketed IPv6.
- Malformed and relative URLs.
- Host-suffix attacks such as `example.com.attacker.test`.
- Apple's ordered list of requested service identifiers.

Broader subdomain/registrable-domain matching is deferred until a
public-suffix-aware implementation exists.

## Settings and enablement UX

Extend:

- `MacPass/MPIntegrationPreferencesController.h` and `.m`.
- `MacPass/Base.lproj/IntegrationPreferences.xib`.
- `MacPass/MPSettingsHelper.h` and `.m`.
- Maintained localization files.

Add an AutoFill section with:

- System provider enabled/disabled state.
- Availability-gated action or instructions to enable it.
- Published databases and last successful publication time.
- Enable current database.
- Remove publication.
- Synchronization and eligibility errors.

Enablement requires an unlocked, successfully saved database and confirmation
that MacPass will store an encrypted device-local AutoFill snapshot which
remains separately available after MacPass locks or quits.

## Explicit non-goals and boundaries

This plan does not change, refactor, remove, or test MacPassHTTP. In particular,
the native AutoFill work does not introduce a shared credential broker solely
to converge plugin behavior, does not preserve MacPassHTTP association
semantics, and does not treat browser capture/update as an MVP requirement.

Any future MacPassHTTP migration or retirement needs its own plan and tickets.
That work may reuse stable credential identifiers or matching utilities only
after evaluating the plugin's compatibility and security requirements on their
own merits.

## Delivery slices

1. Signed extension discovery and Developer ID distribution spike.
2. Snapshot schema and Security.framework encryption spike.
3. Identifier, matching, schema, and tamper tests.
4. Transactional generation store and crash recovery.
5. App publisher from exact successful save revisions.
6. Identity-store synchronization.
7. Password-only extension without cross-request secret caching.
8. Settings, enablement, unpublish, and lifecycle UX.
9. Multi-vault, Save As, key-change, and performance hardening.

Each slice must leave the normal MacPass build and healthy tests passing.

## Required validation matrix

### Build and distribution

- Unsigned/ad-hoc CI compilation.
- Properly signed Development build.
- Developer ID archive, notarization, staple, installation, and discovery.
- Minimum and current supported macOS.
- Correct nested-code runpaths and signatures.

### Publication and recovery

- Every crash point before and after current-generation activation.
- Extension read concurrent with app publication and unpublish.
- Truncated, forged, rolled-back, symlinked, and permission-weakened files.
- Orphan generation cleanup.
- Older publication must never overwrite a newer save.

### Database lifecycle

- KDB and KDBX 3.1, 4, and 4.1 source databases.
- Password-only, key-file-only, and combined composite keys.
- Successful and failed password/key-file changes.
- Save, autosave, Save As, Save To, duplicate, rename, move, replacement,
  revert, and external file change.
- Read-only sources.

### Credential eligibility

- Deleted, trashed, history, template, expired, and meta entries.
- Empty password and empty username.
- Valid references and unsupported interactive placeholders.
- Malformed, Unicode, IPv4, and IPv6 URLs.
- Multiple vaults with colliding entry/root UUIDs.

### Extension and Keychain

- Direct request with UI prohibited.
- Interactive success and cancellation.
- Login-password fallback and unavailable biometry.
- Locked login Keychain and biometric enrollment change.
- Invalid identifier, stale identity, missing generation, and tampered envelope.
- Large-vault latency and extension termination under memory pressure.

### Identity store

- Disabled and enabled states.
- Store Busy retry exhaustion.
- Complete replacement across multiple publications.
- Incremental unsupported.
- Entry deletion and publication removal.
- Interruption between generation activation and identity update.

### Upgrade and cleanup

- Upgrade from a build without AutoFill.
- Snapshot schema migration and unsupported newer schema.
- Downgrade behavior.
- Disable, uninstall, reinstall, and orphaned App Group/Keychain data.

## Definition of the password-provider MVP

The MVP is complete only when an installed, signed MacPass build can:

- Be enabled as a credential provider in macOS.
- Publish eligible credentials from an explicitly enabled database.
- Offer an identity in Safari and at least one non-browser AutoFill client.
- Authenticate user presence and fill the selected username/password while
  MacPass is not running.
- Correctly synchronize saves, deletions, password changes, and unpublish.
- Support multiple published databases without identifier collisions.
- Fail closed on stale, corrupt, or tampered shared state.
- Leave no plaintext password or source composite key on disk or in logs.

Passkeys, OTPs, system password capture, native browser messaging, and all
MacPassHTTP changes are explicitly outside this MVP.
