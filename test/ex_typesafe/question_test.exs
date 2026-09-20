defmodule ExTypesafe.QuestionTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Question
  alias ExTypesafe.Question.{Choice, Noul, Score}

  describe "noul/2" do
    test "builds a Noul with just instructions" do
      q = Question.noul("Does this convey urgency?")

      assert %Noul{type: "noul", instructions: "Does this convey urgency?", criteria: nil} = q
    end

    test "builds a Noul with criteria" do
      q = Question.noul("Is this spam?", %{true: "Promotional", false: "Legitimate"})

      assert %Noul{criteria: %{true: "Promotional", false: "Legitimate"}} = q
    end

    test "encodes to JSON correctly" do
      q = Question.noul("Is this urgent?")

      assert {:ok, json} = Jason.encode(q)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] == "noul"
      assert decoded["instructions"] == "Is this urgent?"
      # criteria should be omitted entirely when nil
      refute Map.has_key?(decoded, "criteria")
    end

    test "encodes criteria to JSON when present" do
      q = Question.noul("Is this spam?", %{true: "Yes", false: "No"})

      assert {:ok, json} = Jason.encode(q)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["criteria"]["true"] == "Yes"
    end
  end

  describe "choice/2" do
    test "builds a Choice question" do
      q = Question.choice("Which team?", %{billing: "Payments", technical: "Bugs"})

      assert %Choice{
               type: "choice",
               instructions: "Which team?",
               criteria: %{billing: "Payments"}
             } = q
    end

    test "encodes to JSON correctly" do
      q = Question.choice("Which team?", %{billing: "Payments", technical: "Bugs"})

      assert {:ok, json} = Jason.encode(q)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] == "choice"
      assert decoded["criteria"]["billing"] == "Payments"
    end
  end

  describe "score/2" do
    test "builds a Score question" do
      q = Question.score("How frustrated?", ["Calm", "Frustrated", "Angry"])

      assert %Score{
               type: "score",
               instructions: "How frustrated?",
               criteria: ["Calm", "Frustrated", "Angry"]
             } = q
    end

    test "encodes to JSON correctly" do
      q = Question.score("How frustrated?", ["Calm", "Frustrated", "Angry"])

      assert {:ok, json} = Jason.encode(q)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] == "score"
      assert decoded["criteria"] == ["Calm", "Frustrated", "Angry"]
    end
  end
end
