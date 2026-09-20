defmodule ExTypesafe do
  @moduledoc """
  Elixir client for the [TypeSafe AI](https://typesafe.ai) API.

  TypeSafe evaluates typed *questions* against a *state* and returns structured answers your
  code can branch on directly — no text parsing required.

  ## Question types

  | Module                       | Type     | Returns                                        |
  |------------------------------|----------|------------------------------------------------|
  | `ExTypesafe.Question.Noul`   | `noul`   | `noul` float (0 = no, 1 = yes)                |
  | `ExTypesafe.Question.Choice` | `choice` | `choice` string + `probabilities` + `confidence` |
  | `ExTypesafe.Question.Score`  | `score`  | `score` float + `probabilities` + `confidence`   |

  ## Quickstart

      # Configure once (reads TYPESAFE_API_KEY from env by default)
      client = ExTypesafe.Client.new()

      # Build typed questions
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
          response.answers["is_urgent"].noul       #=> 0.97
          response.answers["department"].choice    #=> "billing"
          response.answers["frustration"].score    #=> 1.83

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

  `429 Too Many Requests` and `529 Overloaded` responses are retried automatically with
  exponential backoff. Configure `:max_retries` and `:retry_delay_ms` on the client.
  """

  alias ExTypesafe.Client
  alias ExTypesafe.Error
  alias ExTypesafe.Response

  @typedoc "The content to evaluate: a string, map, or list."
  @type state :: String.t() | map() | list()

  @typedoc "A map of question keys to typed Question structs."
  @type questions :: %{(String.t() | atom()) => ExTypesafe.Question.t()}

  @doc """
  Evaluates typed questions against a state using the TypeSafe `systemone` endpoint.

  All questions in the map are evaluated in parallel and in isolation against the same state
  in a single API call.

  Returns `{:ok, ExTypesafe.Response.t()}` or `{:error, ExTypesafe.Error.t()}`.

  ## Parameters

  - `client` — A client built with `ExTypesafe.Client.new/1`.
  - `state` — The content to evaluate: a plain string for text, or a map/list for structured data
    (e.g. chat logs, records, application state).
  - `questions` — A map of arbitrary keys to question structs. Answers are returned under the
    same keys.
  - `opts` — Optional keyword list:
    - `:model` — Override the client's default model for this request.

  ## Examples

      client = ExTypesafe.Client.new(api_key: "ts-...")

      {:ok, response} = ExTypesafe.system_one(client, "I can't log in!", %{
        is_urgent: ExTypesafe.Question.noul("Does this convey urgency?")
      })

      response.answers["is_urgent"].noul  #=> 0.88

  Answers are keyed by the stringified version of whatever key you used in `questions`:

      # atom key → answered under "is_urgent"
      response.answers["is_urgent"]

      # string key → answered under "is_urgent"
      response.answers["is_urgent"]
  """
  @spec system_one(Client.t(), state(), questions(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def system_one(%Client{} = client, state, questions, opts \\ []) do
    Client.evaluate(client, state, questions, opts)
  end
end
