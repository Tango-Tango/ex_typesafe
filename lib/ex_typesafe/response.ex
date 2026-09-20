defmodule ExTypesafe.Response do
  @moduledoc """
  Structs representing a successful TypeSafe API response.

  A `Response` contains:
  - `model` — the model that performed the evaluation
  - `answers` — a map of your question keys to typed `Answer` structs
  - `usage` — token counts for the request
  """

  defmodule Usage do
    @moduledoc "Token usage for a TypeSafe API request."

    @type t :: %__MODULE__{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer()
          }

    defstruct input_tokens: 0, output_tokens: 0
  end

  defmodule NoulAnswer do
    @moduledoc """
    Answer to a `Noul` (yes/no) question.

    `noul` is the probability the answer is yes, on a scale of 0.0 (no) to 1.0 (yes).
    """

    @type t :: %__MODULE__{
            type: String.t(),
            noul: float()
          }

    defstruct type: "noul", noul: nil
  end

  defmodule ChoiceAnswer do
    @moduledoc """
    Answer to a `Choice` question.

    - `choice` — the highest-probability option
    - `probabilities` — every option mapped to its probability (floats summing to 1)
    - `confidence` — how certain the model is (0.0–1.0)
    """

    @type t :: %__MODULE__{
            type: String.t(),
            choice: String.t(),
            probabilities: %{String.t() => float()},
            confidence: float()
          }

    defstruct type: "choice", choice: nil, probabilities: %{}, confidence: nil
  end

  defmodule ScoreAnswer do
    @moduledoc """
    Answer to a `Score` question.

    - `score` — probability-weighted value across your rubric levels
    - `probabilities` — each level mapped to its probability (floats summing to 1)
    - `confidence` — how certain the model is (0.0–1.0)
    """

    @type t :: %__MODULE__{
            type: String.t(),
            score: float(),
            probabilities: [float()],
            confidence: float()
          }

    defstruct type: "score", score: nil, probabilities: [], confidence: nil
  end

  @type answer :: NoulAnswer.t() | ChoiceAnswer.t() | ScoreAnswer.t()

  @type t :: %__MODULE__{
          model: String.t(),
          answers: %{String.t() => answer()},
          usage: Usage.t()
        }

  defstruct model: nil, answers: %{}, usage: nil

  @doc """
  Parses a raw API response map (as decoded JSON) into a `Response` struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      model: map["model"],
      answers: parse_answers(map["answers"] || %{}),
      usage: parse_usage(map["usage"])
    }
  end

  defp parse_answers(answers) when is_map(answers) do
    Map.new(answers, fn {key, value} -> {key, parse_answer(value)} end)
  end

  defp parse_answer(%{"type" => "noul"} = a) do
    %NoulAnswer{type: "noul", noul: a["noul"]}
  end

  defp parse_answer(%{"type" => "choice"} = a) do
    %ChoiceAnswer{
      type: "choice",
      choice: a["choice"],
      probabilities: a["probabilities"] || %{},
      confidence: a["confidence"]
    }
  end

  defp parse_answer(%{"type" => "score"} = a) do
    %ScoreAnswer{
      type: "score",
      score: a["score"],
      probabilities: a["probabilities"] || [],
      confidence: a["confidence"]
    }
  end

  defp parse_usage(nil), do: %Usage{}

  defp parse_usage(usage) when is_map(usage) do
    %Usage{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0
    }
  end
end
