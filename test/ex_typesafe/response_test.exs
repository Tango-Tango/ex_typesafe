defmodule ExTypesafe.ResponseTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Question
  alias ExTypesafe.Response
  alias ExTypesafe.Response.{ChoiceAnswer, NoulAnswer, ScoreAnswer, UnknownAnswer, Usage}
  alias ExTypesafe.TestSupport.QuestionContainer

  @noul_response %{
    "model" => "jev-1.13.0",
    "answers" => %{
      "is_urgent" => %{"type" => "noul", "noul" => 0.95}
    },
    "usage" => %{"input_tokens" => 296, "output_tokens" => 20}
  }

  @choice_response %{
    "model" => "jev-1.13.0",
    "answers" => %{
      "department" => %{
        "type" => "choice",
        "choice" => "billing",
        "probabilities" => %{"billing" => 0.88, "technical" => 0.12, "sales" => 0.0},
        "confidence" => 0.81
      }
    },
    "usage" => %{"input_tokens" => 318, "output_tokens" => 34}
  }

  @score_response %{
    "model" => "jev-1.13.0",
    "answers" => %{
      "frustration" => %{
        "type" => "score",
        "score" => 1.83,
        "legend" => %{"0" => "Calm", "1" => "Frustrated", "2" => "Angry"},
        "probabilities" => %{"0" => 0.05, "1" => 0.37, "2" => 0.58},
        "confidence" => 0.72
      }
    },
    "usage" => %{"input_tokens" => 310, "output_tokens" => 28}
  }

  describe "from_map/1" do
    test "parses model and usage" do
      response = Response.from_map(@noul_response)

      assert response.model == "jev-1.13.0"
      assert %Usage{input_tokens: 296, output_tokens: 20} = response.usage
    end

    test "keeps server answer IDs as strings without a question map" do
      response = Response.from_map(@noul_response)

      assert %NoulAnswer{type: "noul", noul: 0.95} = response.answers["is_urgent"]
      refute Map.has_key?(response.answers, :is_urgent)
    end

    test "parses a choice answer and typed convenience map" do
      response = Response.from_map(@choice_response)
      answer = response.answers["department"]

      assert %ChoiceAnswer{type: "choice", choice: "billing", confidence: 0.81} = answer
      assert answer.probabilities["billing"] == 0.88
      assert answer.probabilities["technical"] == 0.12
      assert response.choices["department"] == answer
      assert response.nouls == %{}
      assert response.scores == %{}
    end

    test "parses a score answer with map probabilities and legend" do
      response = Response.from_map(@score_response)
      answer = response.answers["frustration"]

      assert %ScoreAnswer{type: "score", score: 1.83, confidence: 0.72} = answer
      assert answer.legend == %{"0" => "Calm", "1" => "Frustrated", "2" => "Angry"}
      assert answer.probabilities == %{"0" => 0.05, "1" => 0.37, "2" => 0.58}
      assert response.scores["frustration"] == answer
    end

    test "retains an unknown answer kind instead of raising" do
      response =
        Response.from_map(%{
          "model" => "jev-future",
          "answers" => %{
            "future" => %{"type" => "rank", "rank" => 2, "explanation" => "new kind"}
          },
          "usage" => %{}
        })

      assert %UnknownAnswer{
               type: "rank",
               raw: %{"type" => "rank", "rank" => 2, "explanation" => "new kind"}
             } = response.answers["future"]

      assert response.nouls == %{}
      assert response.choices == %{}
      assert response.scores == %{}
    end

    test "retains malformed answer data instead of raising" do
      response =
        Response.from_map(%{
          "model" => "jev-future",
          "answers" => %{"future" => ["unexpected"]},
          "usage" => %{}
        })

      assert %UnknownAnswer{type: nil, raw: ["unexpected"]} = response.answers["future"]
    end

    test "handles missing usage and answers gracefully" do
      response = Response.from_map(%{"model" => "jev-1.13.0"})

      assert %Usage{input_tokens: 0, output_tokens: 0} = response.usage
      assert response.answers == %{}
      assert response.nouls == %{}
      assert response.choices == %{}
      assert response.scores == %{}
    end
  end

  describe "from_map/2" do
    test "restores atom question keys for ergonomic dot access" do
      questions = %{is_urgent: Question.noul("Is this urgent?")}
      response = Response.from_map(@noul_response, questions)

      assert %NoulAnswer{noul: 0.95} = response.answers.is_urgent
      assert response.nouls.is_urgent == response.answers.is_urgent
      refute Map.has_key?(response.answers, "is_urgent")
    end

    test "restores atom keys from a caller-defined question container" do
      questions = %QuestionContainer{is_urgent: Question.noul("Is this urgent?")}
      response = Response.from_map(@noul_response, questions)

      assert %NoulAnswer{noul: 0.95} = response.answers.is_urgent
      refute Map.has_key?(response.answers, "is_urgent")
      refute Map.has_key?(response.answers, :__struct__)
    end

    test "ignores nil fields in caller-defined question containers" do
      questions = %QuestionContainer{is_urgent: Question.noul("Is this urgent?"), department: nil}
      response = Response.from_map(@noul_response, questions)

      assert %NoulAnswer{noul: 0.95} = response.answers.is_urgent
      refute Map.has_key?(response.answers, :department)
    end

    test "preserves string question keys" do
      questions = %{"is_urgent" => Question.noul("Is this urgent?")}
      response = Response.from_map(@noul_response, questions)

      assert %NoulAnswer{noul: 0.95} = response.answers["is_urgent"]
    end

    test "falls back to server string keys for non-map question input without raising" do
      response = Response.from_map(@noul_response, [])

      assert %NoulAnswer{noul: 0.95} = response.answers["is_urgent"]
    end

    test "falls back to server string keys when handed a typed question struct" do
      response = Response.from_map(@noul_response, Question.noul("Is this urgent?"))

      assert %NoulAnswer{noul: 0.95} = response.answers["is_urgent"]
      refute Map.has_key?(response.answers, :is_urgent)
    end
  end

  describe "from_map/3" do
    test "stores a TypeSafe request ID" do
      response = Response.from_map(@noul_response, %{}, "req_123")

      assert response.request_id == "req_123"
    end

    test "falls back to server string keys for non-map question input and keeps the request id" do
      response = Response.from_map(@noul_response, [], "req_123")

      assert %NoulAnswer{noul: 0.95} = response.answers["is_urgent"]
      assert response.request_id == "req_123"
    end
  end
end
