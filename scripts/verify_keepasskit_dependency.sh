#!/bin/bash

set -euo pipefail

readonly expected_repository='orestesgaolin/KeePassKit'
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

if [[ ! -d Carthage/Checkouts/KeePassKit ]]; then
  exit 0
fi

readonly checkout_revision="$(git -C Carthage/Checkouts/KeePassKit rev-parse HEAD)"
readonly checkout_remote="$(git -C Carthage/Checkouts/KeePassKit remote get-url origin)"

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

echo "Verified KeePassKit fork at $checkout_revision."
