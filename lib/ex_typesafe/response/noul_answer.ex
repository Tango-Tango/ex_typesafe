defmodule ExTypesafe.Response.NoulAnswer do
  @moduledoc """
  Answer to a `Noul` (yes/no) question.

  `noul` is the probability the answer is yes, on a scale of 0.0 (no) to 1.0 (yes).
  """

  @type t :: %__MODULE__{
          type: String.t(),
          noul: number() | nil
        }

  defstruct type: "noul", noul: nil
end
