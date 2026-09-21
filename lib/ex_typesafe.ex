defmodule ExTypesafe do
  @moduledoc """
  Elixir client for the [TypeSafe AI](https://typesafe.ai) API.

  TypeSafe evaluates typed *questions* against a *state* and returns structured answers your
  code can branch on directly — no text parsing required.

  ## Question types

  | Module                       | Type     | Returns                                           |
  |------------------------------|----------|---------------------------------------------------|
  | `ExTypesafe.Question.Noul`   | `noul`   | `noul` float (0 = no, 1 = yes)                   |
  | `ExTypesafe.Question.Choice` | `choice` | `choice` string + probabilities + confidence      |
  | `ExTypesafe.Question.Score`  | `score`  | score + legend + probabilities + confidence       |

  ## Quickstart

      # Configure once (reads TYPESAFE_API_KEY from env by default)
      client = ExTypesafe.Client.new()

      # Build typed questions. Atom keys are retained in the response.
      questions = %{
        is_urgent: ExTypesafe.Question.noul("Does this convey urgency?"),
        department: ExTypesafe.Question.choice(
          "Which team should handle this?",
          %{billing: "Payments, invoicing, refunds", technical: "Bugs, outages, integrations"}
        ),
        frustration: ExTypesafe.Question.score(
          "How frustrated is the customer?",
          ["Calm", "Frustrated", "Very angry"]
        )
      }

      state = "Hi, my payouts have been failing for 3 days. I'm losing sales. Please help!"

      case ExTypesafe.system_one(client, state, questions) do
        {:ok, response} ->
          response.answers.is_urgent.noul       #=> 0.97
          response.answers.department.choice    #=> "billing"
          response.answers.frustration.score    #=> 1.83
          response.scores.frustration.legend    #=> %{"0" => "Calm", ...}

        {:error, error} ->
          IO.inspect(error)
      end

  ## Configuration

  See `ExTypesafe.Client.new/1` and `ExTypesafe.Config` for all options.

  Environment variables are supported:

  | Variable                  | Configures         | Default                        |
  |---------------------------|--------------------|--------------------------------|
  | `TYPESAFE_API_KEY`        | API key (required) | —                              |
  | `TYPESAFE_BASE_URL`       | API root URL       | `https://api.typesafe.ai`      |
  | `TYPESAFE_DEFAULT_MODEL`  | Default model      | `jev-latest`                   |

  ## Retries

  `429 Too Many Requests`, `529 Overloaded`, and transport-level connection failures are retried
  automatically with capped exponential backoff. Numeric `Retry-After` (delta seconds) and
  `retry-after-ms` headers are honored when within the configured cap. Configure
  `:max_retries`, `:retry_delay_ms`, and `:max_retry_delay_ms` on the client or per call. A
  transport retry can repeat a POST if the connection fails after the server receives it.
  """

  alias ExTypesafe.Client
  alias ExTypesafe.Error
  alias ExTypesafe.Response

  @typedoc "The content to evaluate: a string, map, or list."
  @type state :: String.t() | map() | list()

  @typedoc "A typed question struct or raw question map for forward-compatible API fields."
  @type question :: ExTypesafe.Question.t() | map()

  @typedoc "A non-empty map of atom or string question keys to questions."
  @type questions :: %{(String.t() | atom()) => question()}

  @doc """
  Evaluates typed questions against a state using the TypeSafe `systemone` endpoint.

  All questions in the map are evaluated in parallel and in isolation against the same state in a
  single API call. Atom question keys are restored in `response.answers`, while string question
  keys remain strings.

  Returns `{:ok, ExTypesafe.Response.t()}` or `{:error, ExTypesafe.Error.t()}`.

  ## Parameters

  - `client` — A client built with `ExTypesafe.Client.new/1`.
  - `state` — The content to evaluate: a plain string for text, or a map/list for structured data
    (e.g. chat logs, records, application state).
  - `questions` — A non-empty map of arbitrary atom or string keys to question structs or raw
    question maps. Answers are returned under the same key form.
  - `opts` — Optional keyword list:
    - `:model` — Override the client's default model for this request.
    - `:extra_body` — Map of forward-compatible request fields. Core request fields take
      precedence.
    - `:max_retries` — Override the client's retry count for this request.
    - `:retry_delay_ms` — Override the initial retry delay for this request.
    - `:max_retry_delay_ms` — Override the maximum retry delay for this request.

  ## Examples

      client = ExTypesafe.Client.new(api_key: "ts-...")

      {:ok, response} = ExTypesafe.system_one(client, "I can't log in!", %{
        is_urgent: ExTypesafe.Question.noul("Does this convey urgency?")
      })

      response.answers.is_urgent.noul  #=> 0.88

  String question keys remain strings:

      {:ok, response} = ExTypesafe.system_one(client, "I can't log in!", %{
        "is_urgent" => ExTypesafe.Question.noul("Does this convey urgency?")
      })

      response.answers["is_urgent"].noul  #=> 0.88
  """
  @spec system_one(Client.t(), state(), questions(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def system_one(%Client{} = client, state, questions, opts \\ []) do
    Client.evaluate(client, state, questions, opts)
  end
end
