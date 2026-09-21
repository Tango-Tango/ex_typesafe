defmodule ExTypesafe.Response.UnknownAnswer do
  @moduledoc """
  An answer kind introduced by the API after this client version.

  The raw answer is retained instead of raising while parsing the rest of the response. Upgrade
  the client when first-class support for the answer type becomes available.
  """

  @type t :: %__MODULE__{
          type: String.t() | nil,
          raw: term()
        }

  defstruct type: nil, raw: %{}
end
