# ExTypesafe

[![Hex.pm](https://img.shields.io/hexpm/v/ex_typesafe.svg)](https://hex.pm/packages/ex_typesafe)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_typesafe)

Elixir client for the [TypeSafe AI](https://typesafe.ai) API.

TypeSafe evaluates typed *questions* against a *state* and returns structured answers your code
can branch on directly — no text parsing required. Three question primitives, mixable in a
single call:

| Primitive | Ask | Returns |
|---|---|---|
| **Noul** | Yes/no question | Float 0–1 (probability of "yes") |
| **Choice** | Pick one from a list you define | Chosen option + full probability distribution |
| **Score** | Rate on a rubric you define | Probability-weighted score + rubric legend + probabilities |

## Installation

Add `ex_typesafe` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_typesafe, "~> 0.1"}
  ]
end
```

## Configuration

Set your API key via environment variable (recommended):

```bash
export TYPESAFE_API_KEY="ts-..."
```

Or pass it directly when creating a client:

```elixir
client = ExTypesafe.Client.new(api_key: "ts-...")
```

### All client options

| Option | Env Variable | Default | Description |
|---|---|---|---|
| `:api_key` | `TYPESAFE_API_KEY` | — | **Required.** Your TypeSafe API key. |
| `:base_url` | `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` | API root URL. |
| `:model` | `TYPESAFE_DEFAULT_MODEL` | `jev-latest` | Default model for requests. |
| `:max_retries` | — | `3` | Retry attempts on 429/529 responses and transport failures. |
| `:retry_delay_ms` | — | `500` | Initial retry delay; doubles after each attempt. |
| `:max_retry_delay_ms` | — | `5000` | Maximum backoff delay and accepted `Retry-After` value. |

## Usage

```elixir
# 1. Create a client (reads TYPESAFE_API_KEY from env)
client = ExTypesafe.Client.new()

# 2. Define typed questions. Atom keys are preserved in the response.
questions = %{
  is_urgent: ExTypesafe.Question.noul("Does this message convey urgency?"),
  department: ExTypesafe.Question.choice(
    "Which team should handle this?",
    %{
      billing: "Payments, invoices, and refunds",
      technical: "Bugs, outages, and integrations",
      sales: "Pricing, upgrades, and new accounts"
    }
  ),
  frustration: ExTypesafe.Question.score(
    "How frustrated does the customer seem?",
    ["Calm and polite", "Mildly frustrated", "Very angry"]
  )
}

# 3. Evaluate against a state
state = "Hi, my payouts have been failing for 3 days. I'm losing sales. Please help ASAP!"

case ExTypesafe.system_one(client, state, questions) do
  {:ok, response} ->
    response.answers.is_urgent.noul            # => 0.97
    response.answers.department.choice         # => "billing"
    response.answers.frustration.score         # => 1.92
    response.scores.frustration.legend         # => %{"0" => "Calm and polite", ...}
    response.scores.frustration.probabilities  # => %{"0" => 0.01, "1" => 0.11, "2" => 0.88}
    response.usage.input_tokens                # => 418
    response.request_id                        # => "req_..." when sent by the API

  {:error, %ExTypesafe.Error{status: 429}} ->
    # Retried automatically; this means retries were exhausted.
    :backoff

  {:error, error} ->
    IO.inspect(error)
end
```

### Response keys and typed answer maps

Answer keys retain the same form used in the question map:

```elixir
# Atom input keys provide ergonomic map-dot access.
response.answers.is_urgent.noul
response.choices.department.choice
response.scores.frustration.score

# String input keys remain strings.
questions = %{"is_urgent" => ExTypesafe.Question.noul("Urgent?")}
{:ok, response} = ExTypesafe.system_one(client, state, questions)
response.answers["is_urgent"].noul
```

`response.answers` contains all answer kinds. `response.nouls`, `response.choices`, and
`response.scores` are typed convenience maps. Unknown answer kinds from a newer API are retained
as `ExTypesafe.Response.UnknownAnswer` rather than causing response parsing to fail.

### Structured instructions and criteria

Instructions and criterion descriptions can be strings, maps, or lists. Score levels and Choice
descriptions can also be `nil` when no extra description is needed.

```elixir
questions = %{
  same_person: ExTypesafe.Question.noul(%{
    candidate: %{name: "Jane Doe", location: "Austin, TX"},
    question: "Is the resume for the same person as `candidate`?"
  }),
  routing: ExTypesafe.Question.choice(
    ["Which team should own this?", %{account_tier: "enterprise"}],
    %{
      billing: %{examples: ["invoice", "refund"]},
      technical: nil
    }
  )
}
```

Scores require two through ten ordered levels. Choice questions accept one through 255 options.
The client returns `{:error, %ExTypesafe.Error{status: :validation}}` before making a request
when those constraints or question-key uniqueness are violated.

### Forward-compatible request fields

Raw question maps and `:extra_body` let you use a newly introduced API feature before this package
adds a first-class helper:

```elixir
{:ok, response} =
  ExTypesafe.system_one(
    client,
    "I was charged twice.",
    %{
      billing: %{
        "type" => "noul",
        "instructions" => "Is this about billing?",
        "weight" => 2
      }
    },
    extra_body: %{beam_width: 4}
  )
```

The client always controls `state`, `model`, and `questions`; atom- and string-keyed values for
those fields in `:extra_body` are ignored. Raw question maps pass through without the typed helper
validation, so use them deliberately when targeting a newer API feature.

### Per-request model and retry overrides

```elixir
ExTypesafe.system_one(
  client,
  state,
  questions,
  model: "jev-latest",
  max_retries: 1,
  retry_delay_ms: 100,
  max_retry_delay_ms: 1_000
)
```

## Retries

`429 Too Many Requests`, `529 Overloaded`, and transport-level connection failures are retried
automatically with capped exponential backoff. Numeric `Retry-After` (delta seconds) and
`retry-after-ms` headers are honored when within the configured cap. Configure retries on the
client with `:max_retries`, `:retry_delay_ms`, and `:max_retry_delay_ms`, or override them for an
individual call as shown above.

A transport retry can repeat a POST if the connection fails after TypeSafe received the request.
Set `max_retries: 0` when an at-most-once attempt is more important than automatic recovery.

## Testing

Use `Req.Test` to stub HTTP calls without hitting the network:

```elixir
defmodule MyApp.ClassifierTest do
  use ExUnit.Case, async: true

  setup do
    client = ExTypesafe.Client.new(
      api_key: "ts-test",
      plug: {Req.Test, __MODULE__}
    )

    %{client: client}
  end

  test "classifies urgent tickets", %{client: client} do
    Req.Test.stub(__MODULE__, fn conn ->
      body = Jason.encode!(%{
        "model" => "jev-1.13.0",
        "answers" => %{"is_urgent" => %{"type" => "noul", "noul" => 0.95}},
        "usage" => %{"input_tokens" => 296, "output_tokens" => 20}
      })

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)

    {:ok, response} = ExTypesafe.system_one(client, "Help! Urgent!", %{
      is_urgent: ExTypesafe.Question.noul("Urgent?")
    })

    assert response.answers.is_urgent.noul > 0.8
  end
end
```

## API Reference

- [`ExTypesafe`](https://hexdocs.pm/ex_typesafe/ExTypesafe.html) — Main entry point: `system_one/4`
- [`ExTypesafe.Client`](https://hexdocs.pm/ex_typesafe/ExTypesafe.Client.html) — Client configuration
- [`ExTypesafe.Question`](https://hexdocs.pm/ex_typesafe/ExTypesafe.Question.html) — Question helpers: `noul/2`, `choice/2`, `score/2`
- [`ExTypesafe.Response`](https://hexdocs.pm/ex_typesafe/ExTypesafe.Response.html) — Response and answer structs
- [`ExTypesafe.Error`](https://hexdocs.pm/ex_typesafe/ExTypesafe.Error.html) — Error struct

Full TypeSafe API reference: https://docs.typesafe.ai/api

## License

MIT
