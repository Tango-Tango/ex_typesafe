# Publishing `ex_typesafe`

> **For human maintainers only.** Do not delegate a Hex publication or release tag to an agent.

## Prepare the release

1. Update `CHANGELOG.md`, moving the relevant Unreleased entries under a version and date.
2. Update `@version` in `mix.exs`.
3. Commit the release changes and ensure the working tree is clean.

## Verify and publish

Run the local preflight first. It does not require Hex authentication and does not upload anything:

```bash
scripts/publish --dry-run
```

The preflight fetches dependencies for the development and test environments, checks formatting and
Credo, compiles with warnings treated as errors, runs tests, generates documentation, and builds a
local Hex tarball in a temporary directory.

After reviewing the output, publish interactively:

```bash
scripts/publish
```

Hex will prompt for confirmation and requires an authenticated Hex user. To publish non-interactively
(for example, from a protected CI release job with `HEX_API_KEY` configured), use:

```bash
scripts/publish --yes
```

## Tag the release

After Hex confirms the publication, create and push the matching Git tag:

```bash
git tag v<version>
git push origin v<version>
```

If a publication must be reverted, consult `mix help hex.publish` before acting. Hex has a limited
window for reverting or updating a published package version.
