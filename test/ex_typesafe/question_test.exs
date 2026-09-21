defmodule ExTypesafe.QuestionTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Question
  alias ExTypesafe.Question.{Choice, Noul, Score}

  describe "noul/2" do
    test "builds a Noul with just instructions" do
      question = Question.noul("Does this convey urgency?")

      assert %Noul{type: "noul", instructions: "Does this convey urgency?", criteria: nil} =
               question
    end

    test "builds a Noul with criteria" do
      question = Question.noul("Is this spam?", %{true: "Promotional", false: "Legitimate"})

      assert %Noul{criteria: %{true: "Promotional", false: "Legitimate"}} = question
    end

    test "omits nil criteria while encoding" do
      question = Question.noul("Is this urgent?")

      assert {:ok, json} = Jason.encode(question)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] == "noul"
      assert decoded["instructions"] == "Is this urgent?"
      refute Map.has_key?(decoded, "criteria")
    end

    test "encodes structured instructions and criteria" do
      question =
        Question.noul(
          ["Does this match the candidate?", %{candidate: %{name: "Jane"}}],
          %{true: %{signals: ["same name", "same city"]}, false: nil}
        )

      assert {:ok, json} = Jason.encode(question)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["instructions"] == [
               "Does this match the candidate?",
               %{"candidate" => %{"name" => "Jane"}}
             ]

      assert decoded["criteria"]["true"] == %{"signals" => ["same name", "same city"]}
      assert decoded["criteria"]["false"] == nil
    end
  end

  describe "choice/2" do
    test "builds a Choice question" do
      question = Question.choice("Which team?", %{billing: "Payments", technical: "Bugs"})

      assert %Choice{
               type: "choice",
               instructions: "Which team?",
               criteria: %{billing: "Payments"}
             } = question
    end

    test "encodes structured criteria and nil descriptions" do
      question =
        Question.choice(
          %{question: "Which team?", ticket: %{priority: "high"}},
          %{billing: %{examples: ["invoice", "refund"]}, technical: nil}
        )

      assert {:ok, json} = Jason.encode(question)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["instructions"] == %{
               "question" => "Which team?",
               "ticket" => %{"priority" => "high"}
             }

      assert decoded["criteria"] == %{
               "billing" => %{"examples" => ["invoice", "refund"]},
               "technical" => nil
             }
    end
  end

  describe "score/2" do
    test "builds a Score question" do
      question = Question.score("How frustrated?", ["Calm", "Frustrated", "Angry"])

      assert %Score{
               type: "score",
               instructions: "How frustrated?",
               criteria: ["Calm", "Frustrated", "Angry"]
             } = question
    end

    test "encodes structured and nil score levels" do
      question =
        Question.score(
          ["Rate the request", %{customer: "Ada"}],
          [%{label: "calm"}, nil, ["urgent", "immediate"]]
        )

      assert {:ok, json} = Jason.encode(question)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["instructions"] == ["Rate the request", %{"customer" => "Ada"}]

      assert decoded["criteria"] == [
               %{"label" => "calm"},
               nil,
               ["urgent", "immediate"]
             ]
    end
  end
end
