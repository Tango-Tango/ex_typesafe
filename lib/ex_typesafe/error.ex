defmodule ExTypesafe.Error do
  @moduledoc """
  Represents an error returned by the TypeSafe API or the client itself.

  ## Fields

  - `:status` — HTTP status code (e.g. `401`, `422`, `429`, `529`), `:transport` for
    network-level errors before a response is received, `:validation` for a request rejected
    locally before it is sent, or `:invalid_response` when a successful HTTP response has an
    unexpected body.
  - `:message` — Human-readable description of the error.
  - `:body` — Raw response body (if available), useful for inspecting validation details.
  - `:request_id` — The TypeSafe request ID from `x-typesafe-request-id`, if the server sent one.

  ## Common status codes

  | Status | Meaning                                                                 |
  |--------|-------------------------------------------------------------------------|
  | `401`  | Missing or invalid API key.                                             |
  | `422`  | Request body failed validation (missing field, malformed question, etc). |
  | `429`  | Rate limit exceeded. Retried automatically with exponential backoff.    |
  | `529`  | TypeSafe temporarily overloaded. Retried automatically.                  |
  """

  @type status :: pos_integer() | :transport | :validation | :invalid_response

  @type t :: %__MODULE__{
          status: status(),
          message: String.t(),
          body: term() | nil,
          request_id: String.t() | nil
        }

  defstruct [:status, :message, :body, :request_id]

  @doc false
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{status: status, body: body} = response) when is_map(body) do
    %__MODULE__{
      status: status,
      message: response_message(body, status),
      body: body,
      request_id: request_id_from_response(response)
    }
  end

  def from_response(%Req.Response{status: status, body: body} = response) do
    %__MODULE__{
      status: status,
      message: "HTTP #{status}",
      body: body,
      request_id: request_id_from_response(response)
    }
  end

  @doc false
  @spec validation_error(String.t()) :: t()
  def validation_error(message) when is_binary(message) do
    %__MODULE__{status: :validation, message: message, body: nil, request_id: nil}
  end

  @doc false
  @spec invalid_response(Req.Response.t(), String.t()) :: t()
  def invalid_response(%Req.Response{body: body} = response, message) when is_binary(message) do
    %__MODULE__{
      status: :invalid_response,
      message: message,
      body: body,
      request_id: request_id_from_response(response)
    }
  end

  @doc false
  @spec transport_error(term()) :: t()
  def transport_error(exception) when is_exception(exception) do
    transport_error_message(Exception.message(exception))
  end

  def transport_error(%{message: message}) when is_binary(message) do
    transport_error_message(message)
  end

  def transport_error(reason) when is_binary(reason) do
    transport_error_message(reason)
  end

  def transport_error(reason) do
    transport_error_message(inspect(reason))
  end

  @doc false
  @spec request_id_from_response(Req.Response.t()) :: String.t() | nil
  def request_id_from_response(response) do
    case Req.Response.get_header(response, "x-typesafe-request-id") do
      [request_id | _rest] -> request_id
      [] -> nil
    end
  end

  defp transport_error_message(message) do
    %__MODULE__{
      status: :transport,
      message: redact_bearer_token(message),
      body: nil,
      request_id: nil
    }
  end

  defp redact_bearer_token(message) do
    Regex.replace(~r/Bearer\s+[^\s"']+/, message, "Bearer [REDACTED]")
  end

  defp response_message(%{"message" => message}, _status) when is_binary(message), do: message

  defp response_message(%{"error" => %{"message" => message}}, _status) when is_binary(message),
    do: message

  defp response_message(%{"error" => message}, _status) when is_binary(message), do: message
  defp response_message(%{"detail" => message}, _status) when is_binary(message), do: message
  defp response_message(_body, status), do: "HTTP #{status}"
end
