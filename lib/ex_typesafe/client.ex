defmodule ExTypesafe.Client do
  @moduledoc """
  A configured TypeSafe API client.

  Wraps `Req` to handle authentication, retries, JSON encoding/decoding, and response key
  restoration. Create a client with `new/1` and pass it to `ExTypesafe.system_one/4`.

  ## Example

      client = ExTypesafe.Client.new(api_key: "ts-...")
      # or read from env:
      client = ExTypesafe.Client.new()

  The client is a plain struct — it's safe to create once and reuse across requests.
  """

  alias ExTypesafe.Config
  alias ExTypesafe.Error
  alias ExTypesafe.Question
  alias ExTypesafe.Response

  @typedoc "An opaque client struct. Treat as read-only."
  @type t :: %__MODULE__{
          config: Config.t(),
          req: Req.Request.t()
        }

  @derive {Inspect, except: [:config, :req]}
  defstruct [:config, :req]

  # Status codes that warrant an automatic retry with exponential backoff.
  @retryable_statuses [429, 529]
  @max_choice_options 255
  @min_score_levels 2
  @max_score_levels 10

  @doc """
  Creates a new client.

  Accepts the same options as `ExTypesafe.Config.new/1`. Falls back to environment variables.
  Raises `ArgumentError` if no API key is configured.

  ## Options

  - `:api_key` — TypeSafe API key. Falls back to `TYPESAFE_API_KEY` env var. **Required.**
  - `:base_url` — API root. Falls back to `TYPESAFE_BASE_URL` env var (default: `https://api.typesafe.ai`).
  - `:model` — Default model. Falls back to `TYPESAFE_DEFAULT_MODEL` env var (default: `jev-latest`).
  - `:max_retries` — Retry attempts on 429/529 and transport failures (default: 3).
  - `:retry_delay_ms` — Initial delay in ms, doubles each attempt (default: 500).
  - `:max_retry_delay_ms` — Maximum exponential-backoff delay and accepted `Retry-After` value
    in ms (default: 5000).
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
        json: nil,
        retry: false
      ]
      |> add_plug(plug)
      |> Req.new()

    %__MODULE__{config: config, req: req}
  end

  @doc """
  Evaluates typed or raw questions against a state.

  Returns `{:ok, ExTypesafe.Response.t()}` on success or `{:error, ExTypesafe.Error.t()}` on
  failure, including local validation failures and exhausted retries.

  This is the low-level function. Prefer `ExTypesafe.system_one/4` for the public API.

  ## Parameters

  - `client` — A client built with `new/1`.
  - `state` — The content to evaluate: a string, map, or list.
  - `questions` — A non-empty map of string/atom keys to question structs or raw question maps.
    Response answer keys retain the same atom or string form supplied here.
  - `opts` — Optional keyword list:
    - `:model` — Override the client's default model.
    - `:extra_body` — Map of additional API request fields. Core `state`, `model`, and `questions`
      fields always take precedence.
    - `:max_retries` — Override the client's retry count for this call.
    - `:retry_delay_ms` — Override the initial retry delay for this call.
    - `:max_retry_delay_ms` — Override the maximum retry delay for this call.
  """
  @spec evaluate(t(), ExTypesafe.state(), ExTypesafe.questions(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def evaluate(client, state, questions, opts \\ [])

  def evaluate(%__MODULE__{} = client, state, questions, opts)
      when is_map(questions) and not is_struct(questions) and is_list(opts) do
    evaluate_with_options(client, state, questions, opts, Keyword.keyword?(opts))
  end

  def evaluate(%__MODULE__{}, _state, questions, _opts)
      when not is_map(questions) or is_struct(questions) do
    {:error, Error.validation_error("questions must be a non-struct map")}
  end

  def evaluate(%__MODULE__{}, _state, _questions, _opts) do
    {:error, Error.validation_error("options must be a keyword list")}
  end

  defp evaluate_with_options(_client, _state, _questions, _opts, false) do
    {:error, Error.validation_error("options must be a keyword list")}
  end

  defp evaluate_with_options(client, state, questions, opts, true) do
    with :ok <- validate_questions(questions),
         {:ok, extra_body} <- extra_body(opts),
         {:ok, max_retries, retry_delay_ms, max_retry_delay_ms} <- retry_options(client, opts) do
      model = opts[:model] || client.config.model

      body = build_request_body(extra_body, state, model, questions)

      validate_json_body(body)
      |> execute_request(client, body, questions, max_retries, retry_delay_ms, max_retry_delay_ms)
    end
  end

  defp execute_request(
         :ok,
         client,
         body,
         questions,
         max_retries,
         retry_delay_ms,
         max_retry_delay_ms
       ) do
    do_request(client, body, questions, max_retries, retry_delay_ms, max_retry_delay_ms)
  end

  defp execute_request(
         {:error, %Error{} = error},
         _client,
         _body,
         _questions,
         _max_retries,
         _retry_delay_ms,
         _max_retry_delay_ms
       ) do
    {:error, error}
  end

  defp build_request_body(extra_body, state, model, questions) do
    extra_body
    |> Map.drop([:state, :model, :questions, "state", "model", "questions"])
    |> Map.merge(%{state: state, model: model, questions: questions})
  end

  defp validate_json_body(body) do
    case Jason.encode(body) do
      {:ok, _json} -> :ok
      {:error, _reason} -> {:error, Error.validation_error("request body must be JSON-encodable")}
    end
  rescue
    _exception -> {:error, Error.validation_error("request body must be JSON-encodable")}
  end

  # --- Request and retry handling ---

  defp do_request(client, body, questions, retries_left, delay_ms, max_delay_ms) do
    result =
      Req.post(client.req,
        url: "/v1/systemone",
        json: body
      )

    handle_request_result(result, client, body, questions, retries_left, delay_ms, max_delay_ms)
  end

  defp handle_request_result(
         {:ok, response},
         client,
         body,
         questions,
         retries_left,
         delay_ms,
         max_delay_ms
       ) do
    handle_response(response, client, body, questions, retries_left, delay_ms, max_delay_ms)
  end

  defp handle_request_result(
         {:error, %Req.TransportError{} = exception},
         client,
         body,
         questions,
         retries_left,
         delay_ms,
         max_delay_ms
       ) do
    retry_transport_or_error(
      client,
      body,
      questions,
      exception,
      retries_left,
      delay_ms,
      max_delay_ms
    )
  end

  defp handle_request_result(
         {:error, exception},
         _client,
         _body,
         _questions,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       ) do
    {:error, Error.transport_error(exception)}
  end

  defp handle_response(
         %Req.Response{status: status, body: response_body} = response,
         _client,
         _body,
         questions,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       )
       when status >= 200 and status < 300 and is_map(response_body) do
    parse_success_response(response, response_body, questions)
  end

  defp handle_response(
         %Req.Response{status: status} = response,
         _client,
         _body,
         _questions,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       )
       when status >= 200 and status < 300 do
    {:error, Error.invalid_response(response, "Expected a JSON object response body")}
  end

  defp handle_response(
         %Req.Response{status: status} = response,
         client,
         body,
         questions,
         retries_left,
         delay_ms,
         max_delay_ms
       )
       when status in @retryable_statuses do
    retry_or_error(client, body, questions, response, retries_left, delay_ms, max_delay_ms)
  end

  defp handle_response(
         response,
         _client,
         _body,
         _questions,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       ) do
    {:error, Error.from_response(response)}
  end

  defp parse_success_response(response, %{"answers" => answers} = response_body, questions)
       when is_map(answers) do
    {:ok, Response.from_map(response_body, questions, Error.request_id_from_response(response))}
  end

  defp parse_success_response(response, %{"answers" => _answers}, _questions) do
    {:error, Error.invalid_response(response, "Expected the response answers field to be a map")}
  end

  defp parse_success_response(response, _response_body, _questions) do
    {:error,
     Error.invalid_response(response, "Expected the response body to include an answers map")}
  end

  defp retry_or_error(client, body, questions, response, retries_left, delay_ms, max_delay_ms)
       when retries_left > 0 do
    Process.sleep(retry_delay(response, delay_ms, max_delay_ms))

    do_request(
      client,
      body,
      questions,
      retries_left - 1,
      next_retry_delay(delay_ms, max_delay_ms),
      max_delay_ms
    )
  end

  defp retry_or_error(
         _client,
         _body,
         _questions,
         response,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       ) do
    {:error, Error.from_response(response)}
  end

  defp retry_transport_or_error(
         client,
         body,
         questions,
         _exception,
         retries_left,
         delay_ms,
         max_delay_ms
       )
       when retries_left > 0 do
    Process.sleep(min(delay_ms, max_delay_ms))

    do_request(
      client,
      body,
      questions,
      retries_left - 1,
      next_retry_delay(delay_ms, max_delay_ms),
      max_delay_ms
    )
  end

  defp retry_transport_or_error(
         _client,
         _body,
         _questions,
         exception,
         _retries_left,
         _delay_ms,
         _max_delay_ms
       ) do
    {:error, Error.transport_error(exception)}
  end

  # --- Local request validation ---

  defp validate_questions(questions) do
    with :ok <- validate_nonempty_questions(questions),
         :ok <- validate_question_keys(questions) do
      validate_question_definitions(questions)
    end
  end

  defp validate_nonempty_questions(questions) when map_size(questions) == 0 do
    {:error, Error.validation_error("at least one question is required")}
  end

  defp validate_nonempty_questions(_questions), do: :ok

  defp validate_question_keys(questions) do
    questions
    |> Enum.reduce_while({:ok, MapSet.new()}, &validate_question_key/2)
    |> case do
      {:ok, _seen} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp validate_question_key({key, _question}, {:ok, seen}) do
    case wire_key(key) do
      {:ok, encoded_key} -> validate_unique_question_key(encoded_key, seen)
      {:error, %Error{} = error} -> {:halt, {:error, error}}
    end
  end

  defp validate_unique_question_key(encoded_key, seen) do
    if MapSet.member?(seen, encoded_key) do
      {:halt,
       {:error,
        Error.validation_error(
          "question keys must not collide after JSON encoding: #{inspect(encoded_key)}"
        )}}
    else
      {:cont, {:ok, MapSet.put(seen, encoded_key)}}
    end
  end

  defp wire_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp wire_key(key) when is_binary(key), do: {:ok, key}

  defp wire_key(key) do
    {:error,
     Error.validation_error("question keys must be atoms or strings, got: #{inspect(key)}")}
  end

  defp validate_question_definitions(questions) do
    Enum.reduce_while(questions, :ok, fn {key, question}, :ok ->
      case validate_question(question, key) do
        :ok -> {:cont, :ok}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_question(%Question.Noul{criteria: criteria}, key),
    do: validate_noul(criteria, key)

  defp validate_question(%Question.Choice{criteria: criteria}, key),
    do: validate_choice(criteria, key)

  defp validate_question(%Question.Score{criteria: criteria}, key),
    do: validate_score(criteria, key)

  # Raw maps are intentionally passed through without typed-question validation. They provide an
  # escape hatch for API fields and question kinds introduced after this client version.
  defp validate_question(question, _key) when is_map(question) and not is_struct(question),
    do: :ok

  defp validate_question(question, key) do
    {:error,
     Error.validation_error(
       "question #{inspect(key)} must be a question struct or raw map, got: #{inspect(question)}"
     )}
  end

  defp validate_noul(nil, _key), do: :ok
  defp validate_noul(criteria, _key) when is_map(criteria), do: :ok

  defp validate_noul(_criteria, key) do
    {:error,
     Error.validation_error("Noul question #{inspect(key)} criteria must be a map or nil")}
  end

  defp validate_choice(criteria, key) when is_map(criteria) and map_size(criteria) == 0 do
    {:error, Error.validation_error("Choice question #{inspect(key)} needs at least one option")}
  end

  defp validate_choice(criteria, key)
       when is_map(criteria) and map_size(criteria) > @max_choice_options do
    {:error,
     Error.validation_error(
       "Choice question #{inspect(key)} has more than #{@max_choice_options} options"
     )}
  end

  defp validate_choice(criteria, _key) when is_map(criteria), do: :ok

  defp validate_choice(_criteria, key) do
    {:error, Error.validation_error("Choice question #{inspect(key)} criteria must be a map")}
  end

  defp validate_score(criteria, key) when not is_list(criteria) do
    {:error, Error.validation_error("Score question #{inspect(key)} criteria must be a list")}
  end

  defp validate_score(criteria, key) when length(criteria) < @min_score_levels do
    {:error,
     Error.validation_error(
       "Score question #{inspect(key)} needs at least #{@min_score_levels} criteria"
     )}
  end

  defp validate_score(criteria, key) when length(criteria) > @max_score_levels do
    {:error,
     Error.validation_error(
       "Score question #{inspect(key)} supports at most #{@max_score_levels} criteria"
     )}
  end

  defp validate_score(_criteria, _key), do: :ok

  defp extra_body(opts) do
    case Keyword.get(opts, :extra_body, %{}) do
      extra_body when is_map(extra_body) and not is_struct(extra_body) -> {:ok, extra_body}
      _extra_body -> {:error, Error.validation_error("extra_body must be a non-struct map")}
    end
  end

  defp retry_options(client, opts) do
    max_retries = Keyword.get(opts, :max_retries, client.config.max_retries)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, client.config.retry_delay_ms)

    max_retry_delay_ms =
      Keyword.get(opts, :max_retry_delay_ms, client.config.max_retry_delay_ms)

    with :ok <- validate_non_negative_integer(max_retries, "max_retries"),
         :ok <- validate_non_negative_integer(retry_delay_ms, "retry_delay_ms"),
         :ok <- validate_non_negative_integer(max_retry_delay_ms, "max_retry_delay_ms") do
      {:ok, max_retries, retry_delay_ms, max_retry_delay_ms}
    end
  end

  defp validate_non_negative_integer(value, _name) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_negative_integer(value, name) do
    {:error,
     Error.validation_error("#{name} must be a non-negative integer, got: #{inspect(value)}")}
  end

  defp retry_delay(response, fallback_delay_ms, max_delay_ms) do
    case retry_after_delay(response, max_delay_ms) do
      nil -> min(fallback_delay_ms, max_delay_ms)
      retry_after_delay_ms -> retry_after_delay_ms
    end
  end

  defp retry_after_delay(response, max_delay_ms) do
    response
    |> retry_after_ms()
    |> valid_retry_after_delay(max_delay_ms)
  end

  defp retry_after_ms(response) do
    parse_retry_after_ms(Req.Response.get_header(response, "retry-after-ms")) ||
      parse_retry_after_seconds(Req.Response.get_header(response, "retry-after"))
  end

  defp parse_retry_after_ms([value | _rest]), do: parse_non_negative_integer(value)
  defp parse_retry_after_ms([]), do: nil

  defp parse_retry_after_seconds([value | _rest]) do
    case parse_non_negative_integer(value) do
      nil -> nil
      seconds -> seconds * 1_000
    end
  end

  defp parse_retry_after_seconds([]), do: nil

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _other -> nil
    end
  end

  defp valid_retry_after_delay(nil, _max_delay_ms), do: nil
  defp valid_retry_after_delay(delay_ms, max_delay_ms) when delay_ms <= max_delay_ms, do: delay_ms
  defp valid_retry_after_delay(_delay_ms, _max_delay_ms), do: nil

  defp next_retry_delay(delay_ms, max_delay_ms), do: min(delay_ms * 2, max_delay_ms)

  defp add_plug(opts, nil), do: opts
  defp add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
