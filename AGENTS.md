# AGENTS.md — Agent Guide for ex_typesafe

## What this repo is

`ex_typesafe` is a standalone Elixir Hex package — a client for the
[TypeSafe AI](https://typesafe.ai) API. It is **not** part of an umbrella app.
It has no database, no Phoenix, no OTP application of its own. Keep it that way.

The full API surface is a single HTTP endpoint:

```
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer <API_KEY>
```

Requests carry a `state` (string, map, or list) and a `questions` map of typed
question structs. Responses carry typed `answers` under the same keys.
See [API reference](https://docs.typesafe.ai/api) for the full spec.

## Package layout

```
lib/
  ex_typesafe.ex              # Public entry point — system_one/4
  ex_typesafe/
    client.ex                 # Req-based HTTP client, retry logic
    config.ex                 # Option resolution + env var fallbacks
    question.ex               # Noul, Choice, Score structs + helpers
    response.ex               # Response, answer, and usage structs
    error.ex                  # Error struct
test/
  ex_typesafe_test.exs
  ex_typesafe/
    client_test.exs
    config_test.exs
    question_test.exs
    response_test.exs
```

## Key dependencies

| Dep | Purpose |
|-----|---------|
| `req` | HTTP client |
| `jason` | JSON encode/decode |
| `plug` | Test-only — `Req.Test` plug stubs for mocking HTTP |

## Development commands

```bash
mix deps.get          # install dependencies
mix test              # run all tests
mix format            # format code
mix credo --strict    # lint
mix docs              # generate hexdocs
```

All tests use `Req.Test` plug stubs — no live network calls, no API key needed.

## Coding conventions

- **Return `{:ok, result}` / `{:error, reason}`** — no exceptions for control flow
- **Pattern match on function heads** over `case`/`if` in bodies
- **`@spec`** on every public function
- **`@moduledoc` / `@doc`** on every public module and function
- **Never nest modules** in the same file
- `@derive Jason.Encoder` or a custom `Jason.Encoder` impl for structs that
  are serialised — omit `nil` optional fields rather than sending `null`

## Testing conventions

- Every new code path needs a test. Existing tests passing is not sufficient
  for new behaviour.
- Use `Req.Test.stub/2` with a `plug: {Req.Test, __MODULE__}` client for all
  HTTP mocking — never make live requests in tests.
- `async: true` on all test modules.

## Things NOT to do

- Don't add an OTP application, supervisor, or GenServer — this is a pure
  library with no runtime process tree.
- Don't add `Application.get_env` config — configuration is passed explicitly
  via `ExTypesafe.Client.new/1` options or env vars resolved at call time.
- Don't reach outside `lib/` to add middleware, plugs, or adapters for other
  frameworks — keep it dependency-free at runtime except `req` and `jason`.
- Don't remove or rename public functions without a major version bump and a
  `@deprecated` annotation first.

## Publishing checklist (for humans)

1. Update `CHANGELOG.md` — move Unreleased items under a version + date
2. Bump `@version` in `mix.exs`
3. `mix hex.publish`
4. Tag: `git tag v<version> && git push origin v<version>`
