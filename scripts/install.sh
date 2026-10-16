#!/usr/bin/env bash
# First-time install: the one app (latest release) + the hidden test copy for agent tests.
#   app = the latest release tag (or v0.1 if none yet) · test copy = the working tree, in .build/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
"$ROOT/scripts/release.sh" "${LATEST:-v0.1}"
"$ROOT/scripts/test-copy.sh"
