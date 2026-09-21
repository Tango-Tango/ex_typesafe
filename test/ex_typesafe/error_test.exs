defmodule ExTypesafe.ErrorTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Error

  test "uses an exception's human-readable transport message" do
    error = Error.transport_error(%Req.TransportError{reason: :econnrefused})

    assert %Error{status: :transport, body: nil, request_id: nil} = error
    assert error.message == "connection refused"
  end

  test "preserves supplied map messages and inspects non-message transport reasons" do
    assert %Error{status: :transport, message: "custom transport message"} =
             Error.transport_error(%{message: "custom transport message"})

    assert %Error{status: :transport, message: ":unexpected"} =
             Error.transport_error(:unexpected)
  end

  test "extracts nested API error messages and request IDs" do
    response =
      Req.Response.new(status: 422, body: %{"error" => %{"message" => "Invalid question"}})
      |> Req.Response.put_header("x-typesafe-request-id", "req_nested")

    assert %Error{
             status: 422,
             message: "Invalid question",
             body: %{"error" => %{"message" => "Invalid question"}},
             request_id: "req_nested"
           } = Error.from_response(response)
  end

  test "redacts bearer tokens from transport error messages" do
    error = Error.transport_error("invalid header: Bearer ts-secret-value")

    assert error.message == "invalid header: Bearer [REDACTED]"
    refute error.message =~ "ts-secret-value"
  end

  test "extracts binary error and detail response messages" do
    error_response = Req.Response.new(status: 422, body: %{"error" => "Invalid question"})
    detail_response = Req.Response.new(status: 422, body: %{"detail" => "Missing state"})

    assert %Error{message: "Invalid question"} = Error.from_response(error_response)
    assert %Error{message: "Missing state"} = Error.from_response(detail_response)
  end

  test "retains plain-text API error bodies" do
    response = Req.Response.new(status: 502, body: "upstream unavailable")

    assert %Error{status: 502, message: "HTTP 502", body: "upstream unavailable"} =
             Error.from_response(response)
  end

  test "retains an unexpected successful response body" do
    response =
      Req.Response.new(status: 200, body: ["unexpected"])
      |> Req.Response.put_header("x-typesafe-request-id", "req_invalid")

    assert %Error{
             status: :invalid_response,
             message: "Expected JSON object",
             body: ["unexpected"],
             request_id: "req_invalid"
           } = Error.invalid_response(response, "Expected JSON object")
  end
end
