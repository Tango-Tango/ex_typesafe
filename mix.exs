defmodule ExTypesafe.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/ex_typesafe"

  def project do
    [
      app: :ex_typesafe,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExTypesafe",
      source_url: @source_url,
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # Dev / test
      {:plug, "~> 1.14", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir client for the TypeSafe AI API — evaluate typed questions (Choice, Score, Noul) against any state."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "TypeSafe AI" => "https://typesafe.ai",
        "API docs" => "https://docs.typesafe.ai/api"
      },
      maintainers: []
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
