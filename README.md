# ExTypesafe

[![Hex.pm](https://img.shields.io/hexpm/v/ex_typesafe.svg)](https://hex.pm/packages/ex_typesafe)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ex_typesafe)

Elixir client for the [TypeSafe AI](https://typesafe.ai) API.

TypeSafe evaluates typed *questions* against a *state* and returns structured answers your
code can branch on directly — no text parsing required. Three question primitives, mixable in
a single call:

| Primitive  | Ask                              | Returns                                      |
|------------|----------------------------------|----------------------------------------------|
| **Noul**   | Yes/no question                  | Float 0–1 (probability of "yes")             |
| **Choice** | Pick one from a list you define  | Chosen option + full probability distribution |
| **Score**  | Rate on a rubric you define      | Probability-weighted float across your levels |

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

### All options

| Option           | Env Variable              | Default                        | Description                                |
|------------------|---------------------------|--------------------------------|--------------------------------------------|
| `:api_key`       | `TYPESAFE_API_KEY`        | —                              | **Required.** Your TypeSafe API key.       |
| `:base_url`      | `TYPESAFE_BASE_URL`       | `https://api.typesafe.ai`      | API root URL.                              |
| `:model`         | `TYPESAFE_DEFAULT_MODEL`  | `jev-latest`                   | Default model for requests.                |
| `:max_retries`   | —                         | `3`                            | Retry attempts on 429/529 responses.       |
| `:retry_delay_ms`| —                         | `500`                          | Initial retry delay (doubles each attempt).|

## Usage

```elixir
# 1. Create a client (reads TYPESAFE_API_KEY from env)
client = ExTypesafe.Client.new()

# 2. Define typed questions
questions = %{
  is_urgent:   ExTypesafe.Question.noul("Does this message convey urgency?"),
  department:  ExTypesafe.Question.choice(
    "Which team should handle this?",
    %{
      billing:   "Payments, invoices, and refunds",
      technical: "Bugs, outages, and integrations",
      sales:     "Pricing, upgrades, and new accounts"
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
    IO.inspect(response.answers["is_urgent"].noul)        # => 0.97
    IO.inspect(response.answers["department"].choice)     # => "billing"
    IO.inspect(response.answers["frustration"].score)     # => 1.92
    IO.inspect(response.usage.input_tokens)               # => 418

  {:error, %ExTypesafe.Error{status: 429}} ->
    # Retried automatically; this means retries were exhausted
    :backoff

  {:error, error} ->
    IO.inspect(error)
end
```

### Structured instructions

Questions can reference data in `instructions` or `state` using structured maps:

```elixir
questions = %{
  same_person: ExTypesafe.Question.noul(%{
    candidate: %{name: "Jane Doe", location: "Austin, TX"},
    question: "Is the resume for the same person as `candidate`?"
  })
}
```

### Per-request model override

```elixir
ExTypesafe.system_one(client, state, questions, model: "jev-latest")
```

## Retries

`429 Too Many Requests` and `529 Overloaded` responses are retried automatically with
exponential backoff. Configure with `:max_retries` and `:retry_delay_ms` on the client.

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

    assert response.answers["is_urgent"].noul > 0.8
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
