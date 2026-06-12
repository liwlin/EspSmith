#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs frontend (npm) dependencies and prefetches Rust (cargo) dependencies
# so type-checking, builds and tests work inside the web sandbox.
set -euo pipefail

# Only needed in the remote (web) execution environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# package-lock.json records registry.npmmirror.com tarball URLs, which are
# unreachable from the web sandbox. Use the official registry and rewrite the
# mirror hosts recorded in the lockfile (user-level config only; the lockfile
# itself is left untouched).
npm config set --location=user registry https://registry.npmjs.org/
npm config set --location=user replace-registry-host always

npm install

# Put the cargo wrapper on PATH for the whole session (see hooks/bin/cargo:
# it redirects the rsproxy.cn crates.io mirror back to the official index).
echo "export PATH=\"$CLAUDE_PROJECT_DIR/.claude/hooks/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Prefetch all Rust dependencies so cargo check/test work right away.
PATH="$CLAUDE_PROJECT_DIR/.claude/hooks/bin:$PATH" \
  cargo fetch --manifest-path src-tauri/Cargo.toml

echo "Session start hook completed: npm dependencies installed, cargo dependencies prefetched."
