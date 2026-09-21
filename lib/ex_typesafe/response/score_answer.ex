defmodule ExTypesafe.Response.ScoreAnswer do
  @moduledoc """
  Answer to a `Score` question.

  - `score` — probability-weighted value across your rubric levels
  - `legend` — each numeric rubric level mapped to its description
  - `probabilities` — each numeric rubric level mapped to its probability
  - `confidence` — how certain the model is (0.0–1.0)
  """

  @type t :: %__MODULE__{
          type: String.t(),
          score: number() | nil,
          legend: %{optional(String.t()) => ExTypesafe.Question.entry()},
          probabilities: %{optional(String.t()) => number()},
          confidence: number() | nil
        }

  defstruct type: "score", score: nil, legend: %{}, probabilities: %{}, confidence: nil
end
