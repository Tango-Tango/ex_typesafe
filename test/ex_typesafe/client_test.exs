defmodule ExTypesafe.ClientTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Client
  alias ExTypesafe.Error
  alias ExTypesafe.Question
  alias ExTypesafe.Response
  alias ExTypesafe.Response.UnknownAnswer
  alias ExTypesafe.TestSupport.QuestionContainer

  defp test_client(opts \\ []) do
    Client.new(
      Keyword.merge(
        [
          api_key: "ts-test-key",
          base_url: "https://api.typesafe.ai",
          model: "jev-latest",
          plug: {Req.Test, __MODULE__}
        ],
        opts
      )
    )
  end

  defp success_body(answers) do
    %{
      "model" => "jev-1.13.0",
      "answers" => answers,
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
    }
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp stub_success(body) do
    Req.Test.stub(__MODULE__, fn conn -> send_json(conn, 200, body) end)
  end

  defp stub_error(status, body) do
    Req.Test.stub(__MODULE__, fn conn -> send_json(conn, status, body) end)
  end

  describe "new/1" do
    test "raises when the supplied api_key is invalid" do
      assert_raise ArgumentError, ~r/non-empty printable string/, fn ->
        Client.new(api_key: "")
      end
    end

    test "accepts an api_key option without exposing it through Inspect" do
      client = Client.new(api_key: "ts-key")

      assert %Client{} = client
      refute inspect(client) =~ "ts-key"
    end
  end

  describe "evaluate/4 — successful responses" do
    test "restores atom question keys and exposes typed answer maps" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-typesafe-request-id", "req_123")
        |> send_json(200, %{
          "model" => "jev-1.13.0",
          "answers" => %{
            "is_urgent" => %{"type" => "noul", "noul" => 0.95},
            "department" => %{
              "type" => "choice",
              "choice" => "billing",
              "probabilities" => %{"billing" => 0.9, "technical" => 0.1},
              "confidence" => 0.85
            },
            "frustration" => %{
              "type" => "score",
              "score" => 2.1,
              "legend" => %{"0" => "Calm", "1" => "Frustrated", "2" => "Angry"},
              "probabilities" => %{"0" => 0.1, "1" => 0.2, "2" => 0.7},
              "confidence" => 0.78
            }
          },
          "usage" => %{"input_tokens" => 400, "output_tokens" => 60}
        })
      end)

      questions = %{
        is_urgent: Question.noul("Urgent?"),
        department: Question.choice("Which team?", %{billing: "Payments", technical: "Bugs"}),
        frustration: Question.score("How frustrated?", ["Calm", "Frustrated", "Angry"])
      }

      assert {:ok, %Response{} = response} =
               Client.evaluate(test_client(), "My account is broken!", questions)

      assert response.answers.is_urgent.noul == 0.95
      assert response.answers.department.choice == "billing"
      assert response.answers.frustration.score == 2.1
      assert response.scores.frustration.legend["2"] == "Angry"
      assert response.scores.frustration.probabilities["2"] == 0.7
      assert response.nouls.is_urgent == response.answers.is_urgent
      assert response.choices.department == response.answers.department
      assert response.request_id == "req_123"
    end

    test "normalizes a caller-defined question container without serializing __struct__" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["questions"] == %{
                 "is_urgent" => %{"type" => "noul", "instructions" => "Urgent?"}
               }

        refute Map.has_key?(parsed["questions"], "__struct__")

        send_json(conn, 200, success_body(%{"is_urgent" => %{"type" => "noul", "noul" => 0.95}}))
      end)

      questions = %QuestionContainer{is_urgent: Question.noul("Urgent?")}

      assert {:ok, response} = Client.evaluate(test_client(), "My account is broken!", questions)
      assert response.answers.is_urgent.noul == 0.95
      refute Map.has_key?(response.answers, "is_urgent")
    end

    test "omits nil fields from a caller-defined question container" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["questions"] == %{
                 "is_urgent" => %{"type" => "noul", "instructions" => "Urgent?"}
               }

        refute Map.has_key?(parsed["questions"], "department")
        refute Map.has_key?(parsed["questions"], "__struct__")

        send_json(conn, 200, success_body(%{"is_urgent" => %{"type" => "noul", "noul" => 0.95}}))
      end)

      questions = %QuestionContainer{is_urgent: Question.noul("Urgent?"), department: nil}

      assert {:ok, response} = Client.evaluate(test_client(), "My account is broken!", questions)
      assert response.answers.is_urgent.noul == 0.95
    end

    test "preserves string question keys" do
      stub_success(success_body(%{"is_urgent" => %{"type" => "noul", "noul" => 0.95}}))

      assert {:ok, response} =
               Client.evaluate(test_client(), "My payouts are failing!", %{
                 "is_urgent" => Question.noul("Does this convey urgency?")
               })

      assert response.answers["is_urgent"].noul == 0.95
      refute Map.has_key?(response.answers, :is_urgent)
      assert response.request_id == nil
    end

    test "sends state, resolved model, and structured question content" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert conn.request_path == "/v1/systemone"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer ts-test-key"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
        assert parsed["state"] == %{"document" => "hello"}
        assert parsed["model"] == "jev-latest"

        assert parsed["questions"]["q"] == %{
                 "type" => "choice",
                 "instructions" => ["classify", %{"ticket" => 42}],
                 "criteria" => %{"billing" => %{"examples" => ["invoice"]}}
               }

        send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
      end)

      assert {:ok, _response} =
               Client.evaluate(test_client(), %{document: "hello"}, %{
                 q:
                   Question.choice(
                     ["classify", %{ticket: 42}],
                     %{billing: %{examples: ["invoice"]}}
                   )
               })
    end

    test "forwards raw question maps and extra request fields without allowing core overrides" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["questions"]["billing"] == %{
                 "type" => "noul",
                 "instructions" => "About billing?",
                 "weight" => 2
               }

        assert parsed["beam_width"] == 4
        assert parsed["model"] == "jev-latest"
        assert parsed["state"] == "I was charged twice."

        send_json(conn, 200, success_body(%{"billing" => %{"type" => "noul", "noul" => 0.8}}))
      end)

      assert {:ok, response} =
               Client.evaluate(
                 test_client(),
                 "I was charged twice.",
                 %{
                   billing: %{
                     "type" => "noul",
                     "instructions" => "About billing?",
                     "weight" => 2
                   }
                 },
                 extra_body:
                   Map.merge(
                     %{
                       "model" => "string-must-not-override",
                       "state" => "string-must-not-override",
                       "questions" => %{}
                     },
                     %{beam_width: 4, model: "atom-must-not-override"}
                   )
               )

      assert response.answers.billing.noul == 0.8
    end

    test "passes raw question maps through without constraining future API shapes" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["questions"]["future_score"] == %{
                 "type" => "score",
                 "instructions" => "Future rubric",
                 "criteria" => ["single level for a future API"]
               }

        send_json(
          conn,
          200,
          success_body(%{"future_score" => %{"type" => "noul", "noul" => 0.5}})
        )
      end)

      assert {:ok, response} =
               Client.evaluate(test_client(), "hello", %{
                 future_score: %{
                   "type" => "score",
                   "instructions" => "Future rubric",
                   "criteria" => ["single level for a future API"]
                 }
               })

      assert response.answers.future_score.noul == 0.5
    end

    test "accepts any successful 2xx response" do
      Req.Test.stub(__MODULE__, fn conn ->
        send_json(conn, 201, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
      end)

      assert {:ok, response} =
               Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})

      assert response.answers.q.noul == 0.5
    end

    test "returns an invalid-response error for a non-object successful body" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-typesafe-request-id", "req_invalid")
        |> send_json(200, ["unexpected"])
      end)

      assert {:error,
              %Error{
                status: :invalid_response,
                message: "Expected a JSON object response body",
                body: ["unexpected"],
                request_id: "req_invalid"
              }} = Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})
    end

    test "returns an invalid-response error for a malformed answers field" do
      stub_success(%{
        "model" => "jev-1.13.0",
        "answers" => ["unexpected"],
        "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
      })

      assert {:error,
              %Error{
                status: :invalid_response,
                message: "Expected the response answers field to be a map",
                body: %{"answers" => ["unexpected"]}
              }} = Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})
    end

    test "returns an invalid-response error when answers are missing" do
      stub_success(%{
        "model" => "jev-1.13.0",
        "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
      })

      assert {:error,
              %Error{
                status: :invalid_response,
                message: "Expected the response body to include an answers map"
              }} = Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})
    end

    test "allows a per-call model override" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["model"] == "jev-custom"

        send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
      end)

      assert {:ok, _response} =
               Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")},
                 model: "jev-custom"
               )
    end

    test "preserves unknown answer kinds" do
      stub_success(success_body(%{"future" => %{"type" => "rank", "rank" => 2}}))

      assert {:ok, response} =
               Client.evaluate(test_client(), "hello", %{future: %{"type" => "rank"}})

      assert %UnknownAnswer{type: "rank", raw: %{"type" => "rank", "rank" => 2}} =
               response.answers.future
    end
  end

  describe "evaluate/4 — local validation" do
    test "rejects empty question maps and all-nil struct containers before a request is made" do
      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", %{})

      assert message =~ "at least one question"

      assert {:error, %Error{status: :validation, message: ^message}} =
               Client.evaluate(test_client(), "hello", %QuestionContainer{})
    end

    test "rejects non-map and typed question containers, invalid keys, and invalid question values" do
      assert {:error, %Error{status: :validation, message: "questions must be a map or struct"}} =
               Client.evaluate(test_client(), "hello", [])

      assert {:error, %Error{status: :validation, message: typed_container_message}} =
               Client.evaluate(test_client(), "hello", Question.noul("test?"))

      assert typed_container_message =~ "container map or struct, not a question struct"

      assert {:error, %Error{status: :validation, message: key_message}} =
               Client.evaluate(test_client(), "hello", %{1 => Question.noul("test?")})

      assert key_message =~ "question keys must be atoms or strings"

      assert {:error, %Error{status: :validation, message: question_message}} =
               Client.evaluate(test_client(), "hello", %{q: "not a question"})

      assert question_message =~ "must be a question struct or raw map"

      assert {:error, %Error{status: :validation, message: struct_message}} =
               Client.evaluate(test_client(), "hello", %{q: %Response.NoulAnswer{}})

      assert struct_message =~ "must be a question struct or raw map"
    end

    test "rejects a non-question struct container at the question-value level" do
      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", %Response.NoulAnswer{noul: 0.5})

      assert message =~ "must be a question struct or raw map"
    end

    test "rejects atom and string keys that serialize to the same API key" do
      questions = %{
        :is_urgent => Question.noul("Urgent?"),
        "is_urgent" => Question.noul("Urgent?")
      }

      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", questions)

      assert message =~ "must not collide"
    end

    test "rejects score rubrics outside the API's two to ten level range" do
      assert {:error, %Error{status: :validation, message: too_short}} =
               Client.evaluate(test_client(), "hello", %{
                 score: Question.score("Rate", ["only one"])
               })

      assert too_short =~ "at least 2"

      criteria = Enum.map(0..10, &"level #{&1}")

      assert {:error, %Error{status: :validation, message: too_long}} =
               Client.evaluate(test_client(), "hello", %{
                 score: Question.score("Rate", criteria)
               })

      assert too_long =~ "at most 10"
    end

    test "rejects malformed typed criteria" do
      assert {:error, %Error{status: :validation, message: noul_message}} =
               Client.evaluate(test_client(), "hello", %{
                 q: %Question.Noul{instructions: "test?", criteria: "not a map"}
               })

      assert noul_message =~ "Noul question :q criteria must be a map or nil"

      assert {:error, %Error{status: :validation, message: choice_message}} =
               Client.evaluate(test_client(), "hello", %{
                 q: %Question.Choice{instructions: "test?", criteria: ["not a map"]}
               })

      assert choice_message =~ "Choice question :q criteria must be a map"

      assert {:error, %Error{status: :validation, message: score_message}} =
               Client.evaluate(test_client(), "hello", %{
                 q: %Question.Score{instructions: "test?", criteria: %{not: "a list"}}
               })

      assert score_message =~ "Score question :q criteria must be a list"
    end

    test "rejects nil instructions on typed question structs" do
      for {label, question} <- [
            {:noul, %Question.Noul{criteria: %{true: "yes"}}},
            {:choice, %Question.Choice{criteria: %{a: "A", b: "B"}}},
            {:score, %Question.Score{criteria: ["Low", "High"]}}
          ] do
        assert {:error, %Error{status: :validation, message: message}} =
                 Client.evaluate(test_client(), "hello", %{q: question})

        assert message =~ "instructions must not be nil",
               "expected nil-instructions rejection for #{label}, got: #{message}"
      end
    end

    test "rejects Noul criteria with colliding serialized keys" do
      question =
        Question.noul("Is this true?", %{true => "affirmative", "true" => "also affirmative"})

      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", %{q: question})

      assert message =~ "criteria keys must not collide"
    end

    test "rejects Choice criteria with colliding serialized keys" do
      question =
        Question.choice("Pick one", %{:billing => "Payments", "billing" => "Also payments"})

      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", %{q: question})

      assert message =~ "criteria keys must not collide"
    end

    test "rejects empty and oversized Choice criteria" do
      assert {:error, %Error{status: :validation, message: empty_message}} =
               Client.evaluate(test_client(), "hello", %{
                 choice: Question.choice("Pick", %{})
               })

      assert empty_message =~ "at least one option"

      criteria = Map.new(1..256, fn index -> {"option-#{index}", nil} end)

      assert {:error, %Error{status: :validation, message: oversized_message}} =
               Client.evaluate(test_client(), "hello", %{
                 choice: Question.choice("Pick", criteria)
               })

      assert oversized_message =~ "more than 255"
    end

    test "rejects non-map extra bodies, malformed options, and invalid retry overrides" do
      questions = %{q: Question.noul("test?")}

      assert {:error, %Error{status: :validation, message: "extra_body must be a non-struct map"}} =
               Client.evaluate(test_client(), "hello", questions, extra_body: [:not, :a, :map])

      assert {:error, %Error{status: :validation, message: "options must be a keyword list"}} =
               Client.evaluate(test_client(), "hello", questions, [:not, :a, :keyword])

      assert {:error, %Error{status: :validation, message: message}} =
               Client.evaluate(test_client(), "hello", questions, max_retries: -1)

      assert message =~ "max_retries must be a non-negative integer"

      assert {:error, %Error{status: :validation, message: delay_message}} =
               Client.evaluate(test_client(), "hello", questions, retry_delay_ms: -1)

      assert delay_message =~ "retry_delay_ms must be a non-negative integer"

      assert {:error, %Error{status: :validation, message: max_delay_message}} =
               Client.evaluate(test_client(), "hello", questions, max_retry_delay_ms: -1)

      assert max_delay_message =~ "max_retry_delay_ms must be a non-negative integer"
    end

    test "returns validation errors rather than raising for non-JSON state and extra fields" do
      questions = %{q: Question.noul("test?")}

      assert {:error, %Error{status: :validation, message: state_message}} =
               Client.evaluate(test_client(), {:not, :json}, questions)

      assert state_message =~ "request body must be JSON-encodable"

      assert {:error, %Error{status: :validation, message: extra_body_message}} =
               Client.evaluate(test_client(), "hello", questions, extra_body: %{future: self()})

      assert extra_body_message =~ "request body must be JSON-encodable"

      assert {:error, %Error{status: :validation, message: criteria_message}} =
               Client.evaluate(test_client(), "hello", %{
                 q: Question.noul("test?", %{{:tuple, :key} => "not JSON-encodable"})
               })

      assert criteria_message =~ "criteria keys must be atoms or strings"
    end
  end

  describe "evaluate/4 — API errors and retries" do
    test "returns API errors with the TypeSafe request ID" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-typesafe-request-id", "req_error")
        |> send_json(401, %{"message" => "Invalid API key"})
      end)

      assert {:error, %Error{status: 401, message: "Invalid API key", request_id: "req_error"}} =
               Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})
    end

    test "returns an API error on 422" do
      stub_error(422, %{"message" => "Missing required field: state"})

      assert {:error, %Error{status: 422}} =
               Client.evaluate(test_client(), "hello", %{q: Question.noul("test?")})
    end

    test "exhausts retries on 429 and 529" do
      for status <- [429, 529] do
        Req.Test.stub(__MODULE__, fn conn ->
          send_json(conn, status, %{"message" => "Try again"})
        end)

        assert {:error, %Error{status: ^status}} =
                 Client.evaluate(test_client(max_retries: 0), "hello", %{
                   q: Question.noul("test?")
                 })
      end
    end

    test "honors a server retry-after-ms value within the configured cap" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "0")
          |> send_json(429, %{"message" => "Rate limited"})
        else
          send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
        end
      end)

      started_at = System.monotonic_time(:millisecond)

      assert {:ok, _response} =
               Client.evaluate(
                 test_client(max_retries: 0),
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 5_000,
                 max_retry_delay_ms: 5_000
               )

      assert System.monotonic_time(:millisecond) - started_at < 1_000
      assert :counters.get(counter, 1) == 2
    end

    test "converts Retry-After seconds to milliseconds" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "1")
          |> send_json(429, %{"message" => "Rate limited"})
        else
          send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
        end
      end)

      started_at = System.monotonic_time(:millisecond)

      assert {:ok, _response} =
               Client.evaluate(
                 test_client(max_retries: 0),
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 0,
                 max_retry_delay_ms: 1_000
               )

      elapsed_ms = System.monotonic_time(:millisecond) - started_at
      assert elapsed_ms >= 900
      assert elapsed_ms < 2_000
    end

    test "ignores over-cap Retry-After values and falls back to exponential backoff" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "10000")
          |> send_json(429, %{"message" => "Rate limited"})
        else
          send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
        end
      end)

      started_at = System.monotonic_time(:millisecond)

      assert {:ok, _response} =
               Client.evaluate(
                 test_client(max_retries: 0),
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 0,
                 max_retry_delay_ms: 1_000
               )

      assert System.monotonic_time(:millisecond) - started_at < 500
    end

    test "caps exponential retry delays" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt < 2 do
          send_json(conn, 429, %{"message" => "Rate limited"})
        else
          send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
        end
      end)

      started_at = System.monotonic_time(:millisecond)

      assert {:ok, _response} =
               Client.evaluate(
                 test_client(max_retries: 0),
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 2,
                 retry_delay_ms: 1_000,
                 max_retry_delay_ms: 1_000
               )

      assert System.monotonic_time(:millisecond) - started_at < 2_500
      assert :counters.get(counter, 1) == 3
    end

    test "uses a per-call retry override" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt == 0 do
          send_json(conn, 429, %{"message" => "Rate limited"})
        else
          send_json(conn, 200, success_body(%{"q" => %{"type" => "noul", "noul" => 0.5}}))
        end
      end)

      assert {:ok, response} =
               Client.evaluate(
                 test_client(max_retries: 0),
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 0
               )

      assert response.answers.q.noul == 0.5
      assert :counters.get(counter, 1) == 2
    end

    test "retries transport errors before returning the final error" do
      client = test_client(max_retries: 0)
      client = %{client | req: %{client.req | adapter: ExTypesafe.TestTransportErrorAdapter}}

      assert {:error, %Error{status: :transport, message: "connection refused"}} =
               Client.evaluate(
                 client,
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 0,
                 max_retry_delay_ms: 0
               )

      assert_receive :transport_attempt
      assert_receive :transport_attempt
    end

    test "does not retry non-transport request errors" do
      client = test_client(max_retries: 0)
      client = %{client | req: %{client.req | adapter: ExTypesafe.TestPermanentErrorAdapter}}

      assert {:error, %Error{status: :transport, message: "permanent request error"}} =
               Client.evaluate(
                 client,
                 "hello",
                 %{q: Question.noul("test?")},
                 max_retries: 1,
                 retry_delay_ms: 0,
                 max_retry_delay_ms: 0
               )

      assert_receive :permanent_attempt
      refute_receive :permanent_attempt
    end
  end
end
