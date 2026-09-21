defmodule ExTypesafe.TestTransportErrorAdapter do
  @moduledoc false

  @spec run(Req.Request.t()) :: {Req.Request.t(), Exception.t()}
  def run(request) do
    send(self(), :transport_attempt)
    {request, %Req.TransportError{reason: :econnrefused}}
  end
end

defmodule ExTypesafe.TestPermanentErrorAdapter do
  @moduledoc false

  @spec run(Req.Request.t()) :: {Req.Request.t(), Exception.t()}
  def run(request) do
    send(self(), :permanent_attempt)
    {request, RuntimeError.exception("permanent request error")}
  end
end

ExUnit.start()
