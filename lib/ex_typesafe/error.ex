defmodule ExTypesafe.Error do
  @moduledoc """
  Represents an error returned by the TypeSafe API or the client itself.

  ## Fields

  - `:status` — HTTP status code (e.g. `401`, `422`, `429`, `529`), or `:transport` for
    network-level errors before a response is received.
  - `:message` — Human-readable description of the error.
  - `:body` — Raw response body map (if available), useful for inspecting validation details.

  ## Common status codes

  | Status | Meaning                                                                 |
  |--------|-------------------------------------------------------------------------|
  | `401`  | Missing or invalid API key.                                             |
  | `422`  | Request body failed validation (missing field, malformed question, etc). |
  | `429`  | Rate limit exceeded. Retried automatically with exponential backoff.    |
  | `529`  | TypeSafe temporarily overloaded. Retried automatically.                  |
  """

  @type status :: pos_integer() | :transport

  @type t :: %__MODULE__{
          status: status(),
          message: String.t(),
          body: map() | nil
        }

  defstruct [:status, :message, :body]

  @doc false
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{status: status, body: body}) when is_map(body) do
    message =
      body["message"] || body["error"] || body["detail"] || "HTTP #{status}"

    %__MODULE__{status: status, message: message, body: body}
  end

  def from_response(%Req.Response{status: status}) do
    %__MODULE__{status: status, message: "HTTP #{status}", body: nil}
  end

  @doc false
  @spec transport_error(Exception.t() | String.t()) :: t()
  def transport_error(%{message: message}) do
    %__MODULE__{status: :transport, message: message, body: nil}
  end

  def transport_error(reason) when is_binary(reason) do
    %__MODULE__{status: :transport, message: reason, body: nil}
  end

  def transport_error(reason) do
    %__MODULE__{status: :transport, message: inspect(reason), body: nil}
  end
end
