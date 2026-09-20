defmodule ExTypesafeTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Client
  alias ExTypesafe.Question

  defp test_client(opts \\ []) do
    Client.new([api_key: "ts-test-key", plug: {Req.Test, __MODULE__}] ++ opts)
  end

  describe "system_one/4" do
    test "delegates to Client.evaluate and returns {:ok, response}" do
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

      {:ok, response} = ExTypesafe.system_one(client, state, questions)

      assert response.model == "jev-1.13.0"
      assert response.answers["is_urgent"].noul == 0.88
    end

    test "passes through model override" do
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

      {:ok, _} =
        ExTypesafe.system_one(client, "hello", %{}, model: "jev-custom")
    end
  end
end
