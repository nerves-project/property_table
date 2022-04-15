defmodule PropertyTable.MixProject do
  use Mix.Project

  def project do
    [
      app: :property_table,
      version: "0.1.0",
      elixir: "~> 1.11",
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs,
        credo: :test,
        "coveralls.circle": :test
      }
    ]
  end

  defp aliases do
    [bench: ["run bench/bench.exs"]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Build dependencies
      {:benchee, "~> 1.0", only: :dev},
      {:credo, "~> 1.6", only: :test, runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14", only: :test, runtime: false},
      {:ex_doc, "~> 0.26", only: :docs, runtime: false}
    ]
  end

  defp description do
    "In-memory key-value store with subscriptions"
  end

  defp dialyzer() do
    [
      flags: [:race_conditions, :unmatched_returns, :error_handling, :underspecs],
      list_unused_filters: true,
      plt_file: {:no_warn, "_build/plts/dialyzer.plt"}
    ]
  end
end
