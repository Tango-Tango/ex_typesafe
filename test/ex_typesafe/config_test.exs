defmodule ExTypesafe.ConfigTest do
  use ExUnit.Case, async: false

  alias ExTypesafe.Config

  describe "new/1" do
    test "uses provided options without exposing the API key through Inspect" do
      config =
        Config.new(
          api_key: "ts-key",
          base_url: "http://localhost",
          model: "jev-test",
          max_retry_delay_ms: 123
        )

      assert config.api_key == "ts-key"
      assert config.base_url == "http://localhost"
      assert config.model == "jev-test"
      assert config.max_retry_delay_ms == 123
      refute inspect(config) =~ "ts-key"
    end

    test "defaults to env variables" do
      System.put_env("TYPESAFE_API_KEY", "env-key")
      System.put_env("TYPESAFE_BASE_URL", "http://env-host")
      System.put_env("TYPESAFE_DEFAULT_MODEL", "jev-env")

      config = Config.new()

      assert config.api_key == "env-key"
      assert config.base_url == "http://env-host"
      assert config.model == "jev-env"
    after
      System.delete_env("TYPESAFE_API_KEY")
      System.delete_env("TYPESAFE_BASE_URL")
      System.delete_env("TYPESAFE_DEFAULT_MODEL")
    end

    test "options take precedence over env variables" do
      System.put_env("TYPESAFE_API_KEY", "env-key")

      config = Config.new(api_key: "opt-key")

      assert config.api_key == "opt-key"
    after
      System.delete_env("TYPESAFE_API_KEY")
    end

    test "defaults base_url and model when env not set" do
      config = Config.new(api_key: "ts-key")

      assert config.base_url == "https://api.typesafe.ai"
      assert config.model == "jev-latest"
      assert config.max_retry_delay_ms == 5_000
    end

    test "api_key is nil when neither option nor env var is set" do
      System.delete_env("TYPESAFE_API_KEY")
      config = Config.new()

      assert config.api_key == nil
    end
  end

  describe "validate!/1" do
    test "raises when api_key is nil" do
      System.delete_env("TYPESAFE_API_KEY")
      config = Config.new()

      assert_raise ArgumentError, ~r/API key/, fn ->
        Config.validate!(config)
      end
    end

    test "returns config when api_key and retry settings are valid" do
      config = Config.new(api_key: "ts-key", max_retries: 0, max_retry_delay_ms: 0)

      assert %Config{} = Config.validate!(config)
    end

    test "raises without exposing malformed API key values" do
      config = Config.new(api_key: "ts-secret\ninvalid")

      assert_raise ArgumentError, ~r/non-empty printable string/, fn ->
        Config.validate!(config)
      end
    end

    test "raises for invalid retry settings" do
      config = Config.new(api_key: "ts-key", max_retries: -1)

      assert_raise ArgumentError, ~r/max_retries must be a non-negative integer/, fn ->
        Config.validate!(config)
      end
    end
  end
end
