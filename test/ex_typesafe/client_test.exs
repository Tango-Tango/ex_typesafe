defmodule ExTypesafe.ClientTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Client
  alias ExTypesafe.Error
  alias ExTypesafe.Question
  alias ExTypesafe.Response

  # Helper: builds a client that routes through a Req.Test plug.
  defp test_client(opts \\ []) do
    Client.new([api_key: "ts-test-key", plug: {Req.Test, __MODULE__}] ++ opts)
  end

  defp stub_success(body) do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end)
  end

  defp stub_error(status, body) do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end

  describe "new/1" do
    test "raises when no api_key configured" do
      assert_raise ArgumentError, ~r/API key/, fn ->
        Client.new()
      end
    end

    test "accepts api_key option" do
      client = Client.new(api_key: "ts-key")

      assert %Client{} = client
    end
  end

  describe "evaluate/4 — success" do
    test "returns a parsed Response on 200" do
      stub_success(%{
        "model" => "jev-1.13.0",
        "answers" => %{
          "is_urgent" => %{"type" => "noul", "noul" => 0.95}
        },
        "usage" => %{"input_tokens" => 296, "output_tokens" => 20}
      })

      client = test_client()

      {:ok, response} =
        Client.evaluate(client, "My payouts are failing!", %{
          is_urgent: Question.noul("Does this convey urgency?")
        })

      assert %Response{model: "jev-1.13.0"} = response
      assert response.answers["is_urgent"].noul == 0.95
    end

    test "sends state, model, and questions in request body" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["state"] == "hello"
        assert parsed["model"] == "jev-latest"
        assert is_map(parsed["questions"])

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "jev-1.13.0",
            "answers" => %{"q" => %{"type" => "noul", "noul" => 0.5}},
            "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
          })
        )
      end)

      client = test_client()
      {:ok, _} = Client.evaluate(client, "hello", %{q: Question.noul("test?")})
    end

    test "opts :model overrides client default" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["model"] == "jev-custom"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "jev-custom",
            "answers" => %{},
            "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
          })
        )
      end)

      client = test_client()
      {:ok, _} = Client.evaluate(client, "hello", %{}, model: "jev-custom")
    end

    test "handles multiple question types" do
      stub_success(%{
        "model" => "jev-1.13.0",
        "answers" => %{
          "is_urgent" => %{"type" => "noul", "noul" => 0.9},
          "department" => %{
            "type" => "choice",
            "choice" => "billing",
            "probabilities" => %{"billing" => 0.9, "technical" => 0.1},
            "confidence" => 0.85
          },
          "frustration" => %{
            "type" => "score",
            "score" => 2.1,
            "probabilities" => [0.1, 0.2, 0.7],
            "confidence" => 0.78
          }
        },
        "usage" => %{"input_tokens" => 400, "output_tokens" => 60}
      })

      client = test_client()

      questions = %{
        is_urgent: Question.noul("Urgent?"),
        department: Question.choice("Which team?", %{billing: "Payments", technical: "Bugs"}),
        frustration: Question.score("How frustrated?", ["Calm", "Frustrated", "Angry"])
      }

      {:ok, response} = Client.evaluate(client, "My account is broken!", questions)

      assert response.answers["is_urgent"].noul == 0.9
      assert response.answers["department"].choice == "billing"
      assert response.answers["frustration"].score == 2.1
    end
  end

  describe "evaluate/4 — errors" do
    test "returns {:error, Error} on 401" do
      stub_error(401, %{"message" => "Invalid API key"})

      client = test_client()
      {:error, error} = Client.evaluate(client, "hello", %{})

      assert %Error{status: 401, message: "Invalid API key"} = error
    end

    test "returns {:error, Error} on 422" do
      stub_error(422, %{"message" => "Missing required field: state"})

      client = test_client()
      {:error, error} = Client.evaluate(client, "hello", %{})

      assert %Error{status: 422} = error
    end

    test "exhausts retries on 429 and returns error" do
      # Always respond 429; retries should be exhausted quickly with 0 retries
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, Jason.encode!(%{"message" => "Rate limit exceeded"}))
      end)

      # max_retries: 0 so we don't sleep in tests
      client = test_client(max_retries: 0)
      {:error, error} = Client.evaluate(client, "hello", %{})

      assert %Error{status: 429} = error
    end

    test "exhausts retries on 529 and returns error" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(529, Jason.encode!(%{"message" => "Overloaded"}))
      end)

      client = test_client(max_retries: 0)
      {:error, error} = Client.evaluate(client, "hello", %{})

      assert %Error{status: 529} = error
    end

    test "retries on 429 and succeeds on second attempt" do
      counter = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if attempt == 0 do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(429, Jason.encode!(%{"message" => "Rate limited"}))
        else
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "model" => "jev-1.13.0",
              "answers" => %{"q" => %{"type" => "noul", "noul" => 0.5}},
              "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
            })
          )
        end
      end)

      # max_retries: 1, retry_delay_ms: 0 to avoid sleeping
      client = test_client(max_retries: 1, retry_delay_ms: 0)
      {:ok, response} = Client.evaluate(client, "hello", %{q: Question.noul("test?")})

      assert response.model == "jev-1.13.0"
    end
  end
end
