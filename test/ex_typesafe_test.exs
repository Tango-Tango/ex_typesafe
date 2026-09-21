defmodule ExTypesafeTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Client
  alias ExTypesafe.Question

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

  describe "system_one/4" do
    test "delegates to Client.evaluate and restores atom answer keys" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "jev-1.13.0",
            "answers" => %{
              "is_urgent" => %{"type" => "noul", "noul" => 0.88}
            },
            "usage" => %{"input_tokens" => 300, "output_tokens" => 20}
          })
        )
      end)

      client = test_client()
      state = "I can't log in and I have a demo in 10 minutes."
      questions = %{is_urgent: Question.noul("Does this convey urgency?")}

      assert {:ok, response} = ExTypesafe.system_one(client, state, questions)
      assert response.model == "jev-1.13.0"
      assert response.answers.is_urgent.noul == 0.88
      assert response.nouls.is_urgent == response.answers.is_urgent
    end

    test "passes through model override and extra request fields" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)

        assert parsed["model"] == "jev-custom"
        assert parsed["beam_width"] == 4

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "jev-custom",
            "answers" => %{"q" => %{"type" => "noul", "noul" => 0.5}},
            "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
          })
        )
      end)

      assert {:ok, response} =
               ExTypesafe.system_one(
                 test_client(),
                 "hello",
                 %{q: Question.noul("test?")},
                 model: "jev-custom",
                 extra_body: %{beam_width: 4}
               )

      assert response.answers.q.noul == 0.5
    end
  end
end
