#!/usr/bin/env bash
# First-time install: both channels.
#   stable = the latest release tag (or v0.1 if none yet) · dev = the working tree
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
"$ROOT/scripts/release.sh" "${LATEST:-v0.1}"
"$ROOT/scripts/dev.sh"
