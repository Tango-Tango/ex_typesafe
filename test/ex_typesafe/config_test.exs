defmodule ExTypesafe.ConfigTest do
  use ExUnit.Case, async: true

  alias ExTypesafe.Config

  describe "new/1" do
    test "uses provided options" do
      config = Config.new(api_key: "ts-key", base_url: "http://localhost", model: "jev-test")

      assert config.api_key == "ts-key"
      assert config.base_url == "http://localhost"
      assert config.model == "jev-test"
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

    test "returns config when api_key is present" do
      config = Config.new(api_key: "ts-key")

      assert %Config{} = Config.validate!(config)
    end
  end
end
