defmodule ExTypesafe.Client do
  @moduledoc """
  A configured TypeSafe API client.

  Wraps `Req` to handle authentication, retries, and JSON encoding/decoding.
  Create a client with `new/1` and pass it to `ExTypesafe.system_one/3`.

  ## Example

      client = ExTypesafe.Client.new(api_key: "ts-...")
      # or read from env:
      client = ExTypesafe.Client.new()

  The client is a plain struct — it's safe to create once and reuse across requests.
  """

  alias ExTypesafe.Config
  alias ExTypesafe.Error
  alias ExTypesafe.Response

  @typedoc "An opaque client struct. Treat as read-only."
  @type t :: %__MODULE__{
          config: Config.t(),
          req: Req.Request.t()
        }

  defstruct [:config, :req]

  # Status codes that warrant an automatic retry with exponential backoff.
  @retryable_statuses [429, 529]

  @doc """
  Creates a new client.

  Accepts the same options as `ExTypesafe.Config.new/1`. Falls back to environment variables.
  Raises `ArgumentError` if no API key is configured.

  ## Options

  - `:api_key` — TypeSafe API key. Falls back to `TYPESAFE_API_KEY` env var. **Required.**
  - `:base_url` — API root. Falls back to `TYPESAFE_BASE_URL` env var (default: `https://api.typesafe.ai`).
  - `:model` — Default model. Falls back to `TYPESAFE_DEFAULT_MODEL` env var (default: `jev-latest`).
  - `:max_retries` — Retry attempts on 429/529 (default: 3).
  - `:retry_delay_ms` — Initial delay in ms, doubles each attempt (default: 500).
  - `:plug` — Inject a `Req` plug for testing (e.g. `{Req.Test, :typesafe}`).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    {plug, opts} = Keyword.pop(opts, :plug)

    config =
      opts
      |> Config.new()
      |> Config.validate!()

    req =
      [
        base_url: config.base_url,
        headers: [
          {"authorization", "Bearer #{config.api_key}"},
          {"content-type", "application/json"},
          {"accept", "application/json"}
        ],
        json: nil
      ]
      |> add_plug(plug)
      |> Req.new()

    %__MODULE__{config: config, req: req}
  end

  @doc """
  Evaluates typed questions against a state.

  Returns `{:ok, ExTypesafe.Response.t()}` on success or `{:error, ExTypesafe.Error.t()}` on
  failure (including exhausted retries).

  This is the low-level function. Prefer `ExTypesafe.system_one/3` for the public API.

  ## Parameters

  - `client` — A client built with `new/1`.
  - `state` — The content to evaluate: a string, map, or list.
  - `questions` — A map of string/atom keys to `ExTypesafe.Question` structs.
  - `opts` — Optional keyword list:
    - `:model` — Override the client's default model.
  """
  @spec evaluate(t(), ExTypesafe.state(), ExTypesafe.questions(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def evaluate(%__MODULE__{} = client, state, questions, opts \\ []) do
    model = opts[:model] || client.config.model

    body = %{
      state: state,
      model: model,
      questions: questions
    }

    do_request(client, body, client.config.max_retries, client.config.retry_delay_ms)
  end

  # --- Private helpers ---

  defp do_request(client, body, retries_left, delay_ms) do
    result =
      Req.post(client.req,
        url: "/v1/systemone",
        json: body
      )

    case result do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Response.from_map(body)}

      {:ok, %Req.Response{status: status} = response} when status in @retryable_statuses ->
        if retries_left > 0 do
          Process.sleep(delay_ms)
          do_request(client, body, retries_left - 1, delay_ms * 2)
        else
          {:error, Error.from_response(response)}
        end

      {:ok, response} ->
        {:error, Error.from_response(response)}

      {:error, exception} ->
        {:error, Error.transport_error(exception)}
    end
  end

  defp add_plug(opts, nil), do: opts
  defp add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
