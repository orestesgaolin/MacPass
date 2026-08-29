#!/bin/bash

set -euo pipefail

readonly expected_repository='orestesgaolin/KeePassKit'
readonly checkout_path="${KEEPASSKIT_CHECKOUT_PATH:-Carthage/Checkouts/KeePassKit}"
readonly resolved_line="$(grep -E '^github \"[^\"]+/KeePassKit\" ' Cartfile.resolved || true)"
readonly declared_line="$(grep -E '^github \"[^\"]+/KeePassKit\" ' Cartfile || true)"

if [[ "$declared_line" != github\ \"$expected_repository\"\ * ]]; then
  echo "Cartfile must use github \"$expected_repository\"." >&2
  exit 1
fi

if [[ "$resolved_line" != github\ \"$expected_repository\"\ * ]]; then
  echo "Cartfile.resolved must use github \"$expected_repository\"." >&2
  exit 1
fi

readonly expected_revision="$(printf '%s\n' "$resolved_line" | awk -F\" '{ print $4 }')"
if [[ ! "$expected_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "KeePassKit must be pinned to an immutable 40-character commit." >&2
  exit 1
fi

if [[ "${1:-}" == "--declaration-only" ]]; then
  echo "Verified KeePassKit fork declaration at $expected_revision."
  exit 0
fi

if [[ ! -d "$checkout_path" ]]; then
  exit 0
fi

readonly reference_header="$checkout_path/KeePassKit/Utilites/KPKReferenceBuilder.h"
readonly reference_implementation="$checkout_path/KeePassKit/Utilites/KPKReferenceBuilder.m"
if [[ ! -f "$reference_header" ]] ||
   [[ ! -f "$reference_implementation" ]] ||
   ! grep -q 'KPKFieldReferenceResolution' "$reference_header" ||
   ! grep -q 'collectAllMatches' "$reference_implementation"; then
  echo "KeePassKit checkout does not contain the pinned field-reference API." >&2
  exit 1
fi

if [[ -e "$checkout_path/.git" ]]; then
  readonly checkout_revision="$(git -C "$checkout_path" rev-parse HEAD)"
  readonly checkout_remote="$(git -C "$checkout_path" remote get-url origin)"

  if [[ "$checkout_revision" != "$expected_revision" ]]; then
    echo "KeePassKit checkout is $checkout_revision; expected $expected_revision." >&2
    exit 1
  fi

  case "$checkout_remote" in
    https://github.com/orestesgaolin/KeePassKit|https://github.com/orestesgaolin/KeePassKit.git|git@github.com:orestesgaolin/KeePassKit.git)
      ;;
    *)
      echo "KeePassKit checkout origin is $checkout_remote; expected the orestesgaolin fork." >&2
      exit 1
      ;;
  esac
fi

echo "Verified KeePassKit fork checkout for $expected_revision."
