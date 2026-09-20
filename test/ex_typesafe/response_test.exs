defmodule ExTypesafe.ResponseTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Response
  alias ExTypesafe.Response.{ChoiceAnswer, NoulAnswer, ScoreAnswer, Usage}

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
        "probabilities" => [0.05, 0.37, 0.58],
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

    test "parses a noul answer" do
      response = Response.from_map(@noul_response)

      assert %NoulAnswer{type: "noul", noul: 0.95} = response.answers["is_urgent"]
    end

    test "parses a choice answer" do
      response = Response.from_map(@choice_response)
      answer = response.answers["department"]

      assert %ChoiceAnswer{
               type: "choice",
               choice: "billing",
               confidence: 0.81
             } = answer

      assert answer.probabilities["billing"] == 0.88
      assert answer.probabilities["technical"] == 0.12
    end

    test "parses a score answer" do
      response = Response.from_map(@score_response)
      answer = response.answers["frustration"]

      assert %ScoreAnswer{
               type: "score",
               score: 1.83,
               confidence: 0.72
             } = answer

      assert answer.probabilities == [0.05, 0.37, 0.58]
    end

    test "handles missing usage gracefully" do
      response = Response.from_map(Map.delete(@noul_response, "usage"))

      assert %Usage{input_tokens: 0, output_tokens: 0} = response.usage
    end

    test "handles missing answers gracefully" do
      response = Response.from_map(Map.delete(@noul_response, "answers"))

      assert response.answers == %{}
    end
  end
end
