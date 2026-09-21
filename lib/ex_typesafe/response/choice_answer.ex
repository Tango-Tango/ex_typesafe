defmodule ExTypesafe.Response.ChoiceAnswer do
  @moduledoc """
  Answer to a `Choice` question.

  - `choice` — the highest-probability option
  - `probabilities` — every option mapped to its probability (floats summing to 1)
  - `confidence` — how certain the model is (0.0–1.0)
  """

  @type t :: %__MODULE__{
          type: String.t(),
          choice: String.t() | nil,
          probabilities: %{optional(String.t()) => number()},
          confidence: number() | nil
        }

  defstruct type: "choice", choice: nil, probabilities: %{}, confidence: nil
end
