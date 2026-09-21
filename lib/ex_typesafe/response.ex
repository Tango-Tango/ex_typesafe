defmodule ExTypesafe.Response do
  @moduledoc """
  Structs representing a successful TypeSafe API response.

  A `Response` contains:

  - `model` — the model that performed the evaluation
  - `answers` — every answer keyed exactly as its question was supplied
  - `nouls`, `choices`, and `scores` — typed convenience maps for each answer kind
  - `usage` — token counts for the request
  - `request_id` — the TypeSafe request ID, when the API sent one

  When questions are keyed by atoms, atom keys are restored after decoding JSON, so dot access is
  ergonomic and does not create atoms from API-controlled data:

      response.answers.is_urgent.noul
      response.choices.department.choice
      response.scores.frustration.score
  """

  alias ExTypesafe.Question
  alias ExTypesafe.Response.ChoiceAnswer
  alias ExTypesafe.Response.NoulAnswer
  alias ExTypesafe.Response.ScoreAnswer
  alias ExTypesafe.Response.UnknownAnswer
  alias ExTypesafe.Response.Usage

  @typedoc "A question key preserved from the caller's request."
  @type answer_key :: String.t() | atom()

  @type answer :: NoulAnswer.t() | ChoiceAnswer.t() | ScoreAnswer.t() | UnknownAnswer.t()

  @type t :: %__MODULE__{
          model: String.t() | nil,
          answers: %{optional(answer_key()) => answer()},
          nouls: %{optional(answer_key()) => NoulAnswer.t()},
          choices: %{optional(answer_key()) => ChoiceAnswer.t()},
          scores: %{optional(answer_key()) => ScoreAnswer.t()},
          usage: Usage.t() | nil,
          request_id: String.t() | nil
        }

  defstruct model: nil,
            answers: %{},
            nouls: %{},
            choices: %{},
            scores: %{},
            usage: nil,
            request_id: nil

  @doc """
  Parses a raw API response map (as decoded JSON) into a `Response` struct.

  Since no original question map is available, answer keys remain the string IDs returned by the
  API. Use `from_map/2` when atom keys should be restored.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: from_map(map, %{}, nil)

  @doc """
  Parses a raw API response and restores keys from the supplied question map or struct.

  Struct containers are normalized without their `__struct__` field and omit `nil` fields. Atom
  question keys are reused rather than created from strings. String question keys remain strings.
  The caller is responsible for ensuring that no atom and string key serialize to the same API key;
  `ExTypesafe.Client.evaluate/4` validates that invariant before making a request.
  """
  @spec from_map(map(), term()) :: t()
  def from_map(map, questions) when is_map(map), do: from_map(map, questions, nil)

  @doc false
  @spec from_map(map(), term(), String.t() | nil) :: t()
  def from_map(map, questions, request_id) when is_map(map) do
    {answers, nouls, choices, scores} =
      map
      |> Map.get("answers", %{})
      |> parse_answers(question_key_mapping(Question.normalize_container(questions)))
      |> split_answers()

    %__MODULE__{
      model: map["model"],
      answers: answers,
      nouls: nouls,
      choices: choices,
      scores: scores,
      usage: parse_usage(map["usage"]),
      request_id: request_id
    }
  end

  defp question_key_mapping(questions) when is_map(questions) do
    Enum.reduce(questions, %{}, fn
      {key, _question}, mapping when is_atom(key) -> Map.put(mapping, Atom.to_string(key), key)
      {key, _question}, mapping when is_binary(key) -> Map.put(mapping, key, key)
      _entry, mapping -> mapping
    end)
  end

  defp question_key_mapping(_questions), do: %{}

  defp parse_answers(answers, key_mapping) when is_map(answers) do
    Map.new(answers, fn {key, value} ->
      {Map.get(key_mapping, key, key), parse_answer(value)}
    end)
  end

  defp parse_answers(_answers, _key_mapping), do: %{}

  defp split_answers(answers) do
    Enum.reduce(answers, {answers, %{}, %{}, %{}}, fn
      {key, %NoulAnswer{} = answer}, {all, nouls, choices, scores} ->
        {all, Map.put(nouls, key, answer), choices, scores}

      {key, %ChoiceAnswer{} = answer}, {all, nouls, choices, scores} ->
        {all, nouls, Map.put(choices, key, answer), scores}

      {key, %ScoreAnswer{} = answer}, {all, nouls, choices, scores} ->
        {all, nouls, choices, Map.put(scores, key, answer)}

      {_key, %UnknownAnswer{}}, acc ->
        acc

      {_key, _answer}, acc ->
        acc
    end)
  end

  defp parse_answer(%{"type" => "noul"} = answer) do
    %NoulAnswer{type: "noul", noul: answer["noul"]}
  end

  defp parse_answer(%{"type" => "choice"} = answer) do
    %ChoiceAnswer{
      type: "choice",
      choice: answer["choice"],
      probabilities: answer["probabilities"] || %{},
      confidence: answer["confidence"]
    }
  end

  defp parse_answer(%{"type" => "score"} = answer) do
    %ScoreAnswer{
      type: "score",
      score: answer["score"],
      legend: answer["legend"] || %{},
      probabilities: answer["probabilities"] || %{},
      confidence: answer["confidence"]
    }
  end

  defp parse_answer(%{} = answer) do
    %UnknownAnswer{type: unknown_type(answer), raw: answer}
  end

  defp parse_answer(answer) do
    %UnknownAnswer{raw: answer}
  end

  defp unknown_type(%{"type" => type}) when is_binary(type), do: type
  defp unknown_type(_answer), do: nil

  defp parse_usage(usage) when is_map(usage) do
    %Usage{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0
    }
  end

  defp parse_usage(_usage), do: %Usage{}
end
