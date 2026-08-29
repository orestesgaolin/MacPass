# Field References Implementation Plan

## Goal

Make KeePass field references discoverable, editable, inspectable, and compatible in MacPass while keeping reference parsing and target resolution in the owned KeePassKit fork.

The implementation is ready for manual testing when the forked KeePassKit builds and passes focused tests, MacPass builds with that revision, the reference-builder XIB validates, and the end-to-end UUID workflow is exposed in the running app.

## Current checkpoint (2026-08-29)

- KeePassKit focused field-reference tests pass.
- The full KeePassKit macOS suite passes when its pre-existing unconditional `KPKTestOTP/testEntryOTPPropertiesUpdate` failure is skipped.
- MacPass builds, compiles the changed XIB, links the locally built KeePassKit framework, and launches.
- The first manual feedback pass now resolves standard fields in the inspector and entry table, adds explicit raw-expression editing controls, previews selected source values, and removes recycle-bin entries from the source picker.
- The save-crash feedback pass detaches dynamic nested bindings before selection changes, ignores KeePassKit's detached save-copy notifications at the AppKit boundary, and safely handles an absent clear-password preference value.
- The second presentation feedback pass refreshes on KeePassKit attribute changes, keeps table badges and resolved/raw inspector state synchronized, asks before replacing non-empty values, defaults the builder to the destination field type, and uses a compact vertical builder layout with explicit Cancel and Use actions.
- The full MacPass suite runs but retains unrelated legacy failures in database v1 loading, database search, Auto-Type delay timing, key mapping, and plugin-version comparison.
- KeePassKit is committed and published at `b80b507e5387c02fb1060451645ea1cd6cc4bc36`, and both Carthage files pin that immutable revision from `orestesgaolin/KeePassKit`.
- CI and release builds verify the declared fork, immutable revision, and expected field-reference API before building. Git origin and SHA are also checked when checkout metadata is available; Carthage strips that metadata on hosted runners.

## Repository strategy

- MacPass branch: `feature/field-references`
- KeePassKit branch: `feature/field-references` in `orestesgaolin/KeePassKit`
- Do not target the unmaintained `MacPass/KeePassKit` origin.
- During development, use the local KeePassKit feature worktree and copy its built framework into MacPass. Pin MacPass to an immutable fork commit after the KeePassKit branch is committed and pushed.

## Phase 1: KeePassKit reference model and resolver

1. Add immutable structured field-reference and resolution types.
   - Preserve the raw token and source range.
   - Expose WantedField, SearchIn, and search text.
   - Parse multiple references in source order, case-insensitively.
   - Report unique, ambiguous, and unresolved target resolution without returning the wanted value.
2. Refactor command evaluation to use the same parser and target resolver.
3. Match KeePass simple-expression behavior for non-UUID searches.
   - Case-insensitive terms, quoted phrases, negative terms, and first database-order match.
   - Search evaluated standard fields and custom-field values for compatibility with existing command evaluation.
   - Include expired entries and groups excluded from ordinary search.
4. Correct builder and evaluator behavior.
   - `O` is valid only as SearchIn.
   - UUID output is canonical 32-character undashed text.
   - Invalid or empty criteria cannot be built.
   - Unresolved or malformed references remain raw.
   - Recursive references terminate safely.
5. Add focused parser, resolver, builder, compatibility, and cycle tests.

## Phase 2: MacPass creation workflow (implemented)

1. Replace the dormant `MPReferenceBuilderViewController` implementation.
   - Searchable source-entry picker with title and group breadcrumb.
   - Wanted-field picker for Title, Username, Password, URL, Notes, and UUID.
   - Resolved source-value preview while retaining a canonical UUID-backed expression for insertion; password previews remain concealed.
   - Working Use action; dismissing the transient popover cancels.
2. Expose `Insert Field Reference...` from editable Title, Username, Password, URL, Notes, and custom string fields.
3. Capture the active editor value and selection before opening the builder, commit that value to the model, then apply the completed insertion only if the destination has not changed.
4. Exclude history entries, recycle-bin entries, and the destination entry from creation.

## Phase 3: Resolved presentation and safe editing (implemented)

1. Keep raw reference syntax in the model and database, but resolve Title, Username, Password, URL, and Notes by default in the entry inspector.
2. Add a trailing reference button to each referenced standard field, including Notes. The default state is resolved and read-only; the alternate state exposes the raw expression for editing.
3. Resolve Title, Username, Password, URL, and Notes in the entry table and show a trailing link badge for referenced cells. Concealed passwords are based on the resolved value, never the expression length.
4. Resolve referenced titles in the inspector header and source-entry picker.
5. Add contextual resolution tooltips, including ambiguous and missing targets, without putting referenced password values in labels or tooltips.
6. Refresh visible resolved values when either the destination entry or a referenced source entry changes.
7. Keep presentation refreshes main-thread-only and scoped to the displayed live tree; KeePassKit emits entry-change notifications while `NSDocument` copies a detached tree for saving.
8. Observe both entry and attribute changes. Standard fields are `KPKAttribute` values and do not emit `KPKDidChangeEntryNotification`; defer their UI refresh by one main-loop turn so Cocoa Bindings can finish committing before a field is rebound or made read-only.

## Follow-ups after the second manual test

- Add group breadcrumbs to inspection summaries and a Reveal Entry action.
- Consider applying the same resolved/raw toggle treatment to custom string attributes.

## Validation

- KeePassKit focused and full tests.
- MacPass controller coverage for filtering and canonical construction; exercise range insertion, undo, malformed/missing summaries, and non-disclosure during the initial manual pass.
- Persistence test: raw `{REF:...}` survives save/reopen.
- Runtime behavior tests: copy, URL open, and Auto-Type still expand referenced values.
- `ibtool` validation for changed XIBs (also covered by the MacPass build).
- MacPass app build and focused hosted XCTest with isolated DerivedData and signing disabled where appropriate.
- `git diff --check` and explicit-path staging; preserve unrelated worktree files.

## Deferred unless required by a failing compatibility fixture

- Exact KeePass recursion-depth parity.
- KeePass-specific password confirmation dialogs.
