defmodule ExTypesafe.Client.RequestContext do
  @moduledoc false

  @type t :: %__MODULE__{
          client: ExTypesafe.Client.t(),
          body: binary(),
          questions: map(),
          retries_left: non_neg_integer(),
          delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer()
        }

  defstruct [:client, :body, :questions, :retries_left, :delay_ms, :max_delay_ms]
end
