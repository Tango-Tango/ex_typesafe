# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased

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
