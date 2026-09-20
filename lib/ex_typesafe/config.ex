defmodule ExTypesafe.Config do
  @moduledoc """
  Configuration for the TypeSafe API client.

  Options can be passed directly to `ExTypesafe.Client.new/1` or set via environment variables:

  | Variable                  | Configures         | Default                        |
  |---------------------------|--------------------|--------------------------------|
  | `TYPESAFE_API_KEY`        | API key (required) | —                              |
  | `TYPESAFE_BASE_URL`       | API root URL       | `https://api.typesafe.ai`      |
  | `TYPESAFE_DEFAULT_MODEL`  | Default model      | `jev-latest`                   |
  """

  @default_base_url "https://api.typesafe.ai"
  @default_model "jev-latest"
  @default_max_retries 3
  @default_retry_delay_ms 500

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          model: String.t(),
          max_retries: non_neg_integer(),
          retry_delay_ms: non_neg_integer()
        }

  defstruct api_key: nil,
            base_url: @default_base_url,
            model: @default_model,
            max_retries: @default_max_retries,
            retry_delay_ms: @default_retry_delay_ms

  @doc """
  Builds a `Config` from keyword options, falling back to environment variables and then defaults.

  ## Options

  - `:api_key` — TypeSafe API key. Falls back to `TYPESAFE_API_KEY` env var. **Required.**
  - `:base_url` — Base URL for the API. Falls back to `TYPESAFE_BASE_URL` env var.
  - `:model` — Default model to use. Falls back to `TYPESAFE_DEFAULT_MODEL` env var.
  - `:max_retries` — Max retry attempts on 429/529 responses (default: #{@default_max_retries}).
  - `:retry_delay_ms` — Initial retry delay in ms, doubles each attempt (default: #{@default_retry_delay_ms}).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      api_key: opts[:api_key] || System.get_env("TYPESAFE_API_KEY"),
      base_url: opts[:base_url] || System.get_env("TYPESAFE_BASE_URL") || @default_base_url,
      model: opts[:model] || System.get_env("TYPESAFE_DEFAULT_MODEL") || @default_model,
      max_retries: opts[:max_retries] || @default_max_retries,
      retry_delay_ms: opts[:retry_delay_ms] || @default_retry_delay_ms
    }
  end

  @doc false
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{api_key: nil}) do
    raise ArgumentError,
          "TypeSafe API key is required. Set :api_key option or TYPESAFE_API_KEY environment variable."
  end

  def validate!(%__MODULE__{} = config), do: config
end
