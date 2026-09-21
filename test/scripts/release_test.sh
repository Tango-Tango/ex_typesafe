#!/usr/bin/env bash
# Lightweight deterministic coverage for scripts/release dry-run version helpers.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts"
cp "$root/scripts/release" "$fixture/scripts/release"
cat >"$fixture/mix.exs" <<'MIX'
defmodule Fixture.MixProject do
  @version "1.2.3"
end
MIX
cat >"$fixture/CHANGELOG.md" <<'CHANGELOG'
# Changelog

## [Unreleased]

### Added

- Fixture change.

## [1.2.3] - 2026-01-01

- Previous release.
CHANGELOG

before_mix="$(sha256sum "$fixture/mix.exs")"
before_changelog="$(sha256sum "$fixture/CHANGELOG.md")"

[[ "$(cd "$fixture" && scripts/release prepare --bump patch --dry-run)" == *"1.2.4"* ]]
[[ "$(cd "$fixture" && scripts/release prepare --bump feature --dry-run)" == *"1.3.0"* ]]
[[ "$(cd "$fixture" && scripts/release prepare --bump major --dry-run)" == *"2.0.0"* ]]

[[ "$before_mix" == "$(sha256sum "$fixture/mix.exs")" ]]
[[ "$before_changelog" == "$(sha256sum "$fixture/CHANGELOG.md")" ]]

# Exercise preparation end-to-end against only local Git remotes and a fake gh.
mkdir -p "$fixture/bin"
cat >"$fixture/bin/date" <<'DATE'
#!/usr/bin/env bash
printf '2026-09-21\n'
DATE
cat >"$fixture/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status" | "pr create") exit 0 ;;
  *) exit 1 ;;
esac
GH
chmod +x "$fixture/bin/date" "$fixture/bin/gh"

printf 'remote.git/\n' >"$fixture/.gitignore"
git -C "$fixture" init -b main >/dev/null
git -C "$fixture" config user.email release-test@example.com
git -C "$fixture" config user.name "Release Test"
git -C "$fixture" add .
git -C "$fixture" commit -m initial >/dev/null
git init --bare "$fixture/remote.git" >/dev/null
git -C "$fixture" remote add origin "$fixture/remote.git"
git -C "$fixture" push -u origin main >/dev/null

(
  cd "$fixture"
  PATH="$fixture/bin:$PATH" scripts/release prepare --bump feature
)

grep -q '@version "1.3.0"' "$fixture/mix.exs"
grep -q '^## \[Unreleased\]$' "$fixture/CHANGELOG.md"
grep -q '^## \[1.3.0\] - 2026-09-21$' "$fixture/CHANGELOG.md"
grep -q '^## \[1.2.3\] - 2026-01-01$' "$fixture/CHANGELOG.md"

unreleased_entries="$(awk '
  /^## \[Unreleased\]$/ { collecting = 1; next }
  collecting && /^## \[/ { exit }
  collecting { print }
' "$fixture/CHANGELOG.md" | tr -d '[:space:]')"
[[ -z "$unreleased_entries" ]]

awk '
  /^## \[1\.3\.0\] - 2026-09-21$/ { collecting = 1; next }
  collecting && /^## \[/ { exit }
  collecting { print }
' "$fixture/CHANGELOG.md" | grep -Fqx -- '- Fixture change.'

git -C "$fixture" log -1 --format=%s | grep -qx 'chore: release 1.3.0'
git --git-dir="$fixture/remote.git" show-ref --verify --quiet refs/heads/release/v1.3.0

echo "release script tests passed"
