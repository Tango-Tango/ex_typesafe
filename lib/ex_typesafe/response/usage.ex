defmodule ExTypesafe.Response.Usage do
  @moduledoc "Token usage for a TypeSafe API request."

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  defstruct input_tokens: 0, output_tokens: 0
end
