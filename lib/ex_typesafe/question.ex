defmodule ExTypesafe.Question do
  @moduledoc """
  Typed question structs for the TypeSafe API.

  TypeSafe supports three question primitives that can be mixed freely in a single request:

  - `ExTypesafe.Question.Noul` — yes/no question, returns a probability 0–1
  - `ExTypesafe.Question.Choice` — pick one from a set you define, returns the chosen option + probabilities
  - `ExTypesafe.Question.Score` — rate on a rubric you define, returns a probability-weighted value

  Instructions and criterion descriptions can be strings, structured maps, or lists. This makes
  it possible to keep a question beside the data it references without interpolating that data
  into a string.

  ## Example

      questions = %{
        is_urgent: ExTypesafe.Question.noul("Does this convey urgency?"),
        department: ExTypesafe.Question.choice(
          "Which team should handle this?",
          %{billing: "Payments, invoicing, refunds", technical: "Bugs, outages, integrations"}
        ),
        frustration: ExTypesafe.Question.score(
          "How frustrated is the customer?",
          ["Calm", "Frustrated", "Very angry"]
        )
      }
  """

  @typedoc "A JSON-compatible structured value accepted in question content."
  @type structured_value :: String.t() | number() | boolean() | nil | map() | list()

  @typedoc "A criterion description, including `nil` for undescribed entries."
  @type entry :: String.t() | map() | list() | nil

  @typedoc "Question instructions — always required (nil is not accepted)."
  @type instructions :: String.t() | map() | list()

  defmodule Noul do
    @moduledoc """
    A yes/no question. Returns the probability the answer is yes (0.0–1.0).

    Optionally supply `criteria` to describe what "yes" and "no" mean:

        %ExTypesafe.Question.Noul{
          instructions: "Does this convey urgency?",
          criteria: %{true: "Explicitly time-sensitive", false: "No urgency expressed"}
        }
    """

    @type t :: %__MODULE__{
            instructions: ExTypesafe.Question.instructions(),
            criteria: %{optional(true | false) => ExTypesafe.Question.entry()} | nil
          }

    defstruct type: "noul", instructions: nil, criteria: nil

    defimpl Jason.Encoder do
      def encode(%{type: type, instructions: instructions, criteria: criteria}, opts) do
        map = %{type: type, instructions: instructions}
        map = if is_nil(criteria), do: map, else: Map.put(map, :criteria, criteria)
        Jason.Encode.map(map, opts)
      end
    end
  end

  defmodule Choice do
    @moduledoc """
    Picks one option from a set you define. Returns the chosen option and the full probability
    distribution across all options.

    `criteria` is a map of option name to a description (or `nil` for no description). A
    description can be a string, map, or list. Choice questions accept at most 255 options.

        %ExTypesafe.Question.Choice{
          instructions: "Which team should handle this?",
          criteria: %{
            billing: "Payments, invoicing, refunds",
            technical: "Bugs, outages, integrations",
            sales: "Pricing, upgrades, new accounts"
          }
        }
    """

    @type t :: %__MODULE__{
            instructions: ExTypesafe.Question.instructions(),
            criteria: %{required(atom() | String.t()) => ExTypesafe.Question.entry()}
          }

    @derive Jason.Encoder
    defstruct type: "choice", instructions: nil, criteria: %{}
  end

  defmodule Score do
    @moduledoc """
    Rates the state along a rubric you define. Returns a probability-weighted value across
    your levels.

    `criteria` is an ordered list of two to ten level descriptions. Each description can be a
    string, map, list, or `nil`.

        %ExTypesafe.Question.Score{
          instructions: "How frustrated is the customer?",
          criteria: ["Calm", "Frustrated", "Very angry"]
        }
    """

    @type t :: %__MODULE__{
            instructions: ExTypesafe.Question.instructions(),
            criteria: [ExTypesafe.Question.entry()]
          }

    @derive Jason.Encoder
    defstruct type: "score", instructions: nil, criteria: []
  end

  @type t :: Noul.t() | Choice.t() | Score.t()

  @doc false
  @spec normalize_container(term()) :: term()
  # Returns :question_struct for typed question structs, a nil-stripped plain map for others, or input unchanged.
  def normalize_container(%Noul{}), do: :question_struct
  def normalize_container(%Choice{}), do: :question_struct
  def normalize_container(%Score{}), do: :question_struct

  def normalize_container(container) when is_struct(container) do
    container
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def normalize_container(container), do: container

  @doc """
  Builds a `Noul` question (yes/no).

  ## Parameters

  - `instructions` — The yes/no question to evaluate. Can be a string, structured map, or list.
  - `criteria` — Optional map with `:true` and/or `:false` keys describing what each means.

  ## Examples

      iex> ExTypesafe.Question.noul("Does this convey urgency?")
      %ExTypesafe.Question.Noul{type: "noul", instructions: "Does this convey urgency?", criteria: nil}

      iex> ExTypesafe.Question.noul("Is this spam?", %{true: "Clearly promotional", false: "Legitimate message"})
      %ExTypesafe.Question.Noul{type: "noul", instructions: "Is this spam?", criteria: %{true: "Clearly promotional", false: "Legitimate message"}}
  """
  @spec noul(instructions(), map() | nil) :: Noul.t()
  def noul(instructions, criteria \\ nil) do
    %Noul{instructions: instructions, criteria: criteria}
  end

  @doc """
  Builds a `Choice` question.

  ## Parameters

  - `instructions` — What the model should decide. Can be a string, structured map, or list.
  - `criteria` — Map of option name to a rubric description. Use `nil` for an option needing no
    description; descriptions can also be structured maps or lists.

  ## Examples

      iex> ExTypesafe.Question.choice("Which team should handle this?", %{
      ...>   billing: "Payments, invoicing, refunds",
      ...>   technical: "Bugs, outages, integrations"
      ...> })
      %ExTypesafe.Question.Choice{type: "choice", instructions: "Which team should handle this?", criteria: %{billing: "Payments, invoicing, refunds", technical: "Bugs, outages, integrations"}}
  """
  @spec choice(instructions(), map()) :: Choice.t()
  def choice(instructions, criteria) do
    %Choice{instructions: instructions, criteria: criteria}
  end

  @doc """
  Builds a `Score` question.

  ## Parameters

  - `instructions` — What the model should rate. Can be a string, structured map, or list.
  - `criteria` — Ordered list of two to ten level descriptions, low to high. A level description
    can be a string, structured map, list, or `nil`.

  ## Examples

      iex> ExTypesafe.Question.score("How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"])
      %ExTypesafe.Question.Score{type: "score", instructions: "How frustrated is the customer?", criteria: ["Calm", "Frustrated", "Very angry"]}
  """
  @spec score(instructions(), [entry()]) :: Score.t()
  def score(instructions, criteria) when is_list(criteria) do
    %Score{instructions: instructions, criteria: criteria}
  end
end
