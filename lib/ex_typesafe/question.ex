defmodule ExTypesafe.Question do
  @moduledoc """
  Typed question structs for the TypeSafe API.

  TypeSafe supports three question primitives that can be mixed freely in a single request:

  - `ExTypesafe.Question.Noul` — yes/no question, returns a probability 0–1
  - `ExTypesafe.Question.Choice` — pick one from a set you define, returns the chosen option + probabilities
  - `ExTypesafe.Question.Score` — rate on a rubric you define, returns a probability-weighted value

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

  @type instructions :: String.t() | map()

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
            criteria: %{optional(true | false) => String.t()} | nil
          }

    defstruct type: "noul", instructions: nil, criteria: nil

    defimpl Jason.Encoder do
      def encode(%{type: type, instructions: instructions, criteria: criteria}, opts) do
        map = %{type: type, instructions: instructions}
        map = if criteria, do: Map.put(map, :criteria, criteria), else: map
        Jason.Encode.map(map, opts)
      end
    end
  end

  defmodule Choice do
    @moduledoc """
    Picks one option from a set you define. Returns the chosen option and the full probability
    distribution across all options.

    `criteria` is a map of option name to a description (or `nil` for no description).
    Maximum 255 options per Choice question.

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
            criteria: %{required(atom() | String.t()) => String.t() | nil}
          }

    @derive Jason.Encoder
    defstruct type: "choice", instructions: nil, criteria: %{}
  end

  defmodule Score do
    @moduledoc """
    Rates the state along a rubric you define. Returns a probability-weighted value across
    your levels.

    `criteria` is an ordered list of level descriptions (2–10 levels).

        %ExTypesafe.Question.Score{
          instructions: "How frustrated is the customer?",
          criteria: ["Calm", "Frustrated", "Very angry"]
        }
    """

    @type t :: %__MODULE__{
            instructions: ExTypesafe.Question.instructions(),
            criteria: [String.t()]
          }

    @derive Jason.Encoder
    defstruct type: "score", instructions: nil, criteria: []
  end

  @type t :: Noul.t() | Choice.t() | Score.t()

  @doc """
  Builds a `Noul` question (yes/no).

  ## Parameters
  - `instructions` — The yes/no question to evaluate. Can be a string or a structured map.
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
  - `instructions` — What the model should decide. Can be a string or a structured map.
  - `criteria` — Map of option name to rubric description. Use `nil` value for options needing no description.

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
  - `instructions` — What the model should rate. Can be a string or a structured map.
  - `criteria` — Ordered list of level descriptions (2–10 levels, low to high).

  ## Examples

      iex> ExTypesafe.Question.score("How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"])
      %ExTypesafe.Question.Score{type: "score", instructions: "How frustrated is the customer?", criteria: ["Calm", "Frustrated", "Very angry"]}
  """
  @spec score(instructions(), [String.t()]) :: Score.t()
  def score(instructions, criteria) when is_list(criteria) do
    %Score{instructions: instructions, criteria: criteria}
  end
end
