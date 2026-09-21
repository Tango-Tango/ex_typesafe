# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Atom question keys are restored in `Response.answers`, enabling ergonomic access such as
  `response.answers.is_urgent.noul`; string keys remain strings.
- Typed `Response.nouls`, `Response.choices`, and `Response.scores` convenience maps.
- Score answer `legend` and map-shaped `probabilities`, matching the TypeSafe API response.
- `request_id` on successful responses and API errors when TypeSafe sends
  `x-typesafe-request-id`.
- Raw question maps and `:extra_body` for forward-compatible API fields.
- Caller-defined structs as question containers; non-`nil` fields are encoded as questions
  without serializing `__struct__`, optional `nil` fields are omitted, and atom response keys are
  restored.
- Graceful `UnknownAnswer` parsing for answer kinds introduced after this SDK version.
- Per-request `:max_retries`, `:retry_delay_ms`, and `:max_retry_delay_ms` overrides.
- Capped exponential retry backoff, support for numeric `Retry-After` / `retry-after-ms`, and
  retries for transport-level connection failures.
- Local validation errors for empty/colliding question keys and API question limits.

### Changed

- **Breaking while unreleased:** atom-keyed questions now return atom-keyed `Response.answers`;
  use `response.answers.is_urgent` instead of `response.answers["is_urgent"]` for atom input.
- **Breaking while unreleased:** `ScoreAnswer.probabilities` now matches the API's string-keyed
  map shape rather than a list.
- Question instructions and criteria types/documentation now support structured maps, lists, and
  `nil` descriptions where the API permits them.
- All JSON-object 2xx HTTP responses are accepted as successful evaluations.

## [0.1.0] - 2026-09-20

### Added

- `ExTypesafe.Client` — `Req`-based HTTP client with Bearer auth and configurable
  exponential-backoff retry on `429`/`529` responses
- `ExTypesafe.Config` — option resolution with env var fallbacks
  (`TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`, `TYPESAFE_DEFAULT_MODEL`)
- `ExTypesafe.Question` — typed question structs: `Noul`, `Choice`, `Score`
- `ExTypesafe.Response` — typed answer structs for all three question types
  plus `Usage` token counts
- `ExTypesafe.Error` — unified error struct for API and transport-level failures
- `ExTypesafe.system_one/4` — primary public API wrapping the TypeSafe
  `/v1/systemone` evaluation endpoint
- `Req.Test` plug support via `:plug` client option for zero-network-call testing
