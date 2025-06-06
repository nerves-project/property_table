defmodule PropertyTable.MixProject do
  use Mix.Project

  @version "0.3.1"
  @source_url "https://github.com/nerves-project/property_table"

  def project do
    [
      app: :property_table,
      version: @version,
      elixir: "~> 1.13",
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs,
        credo: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.circle": :test
      }
    ]
  end

  defp aliases do
    [bench: ["run bench/bench.exs"]]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  defp deps do
    [
      # Build dependencies
      {:benchee, "~> 1.0", only: :dev},
      {:credo, "~> 1.6", only: :test, runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.17", only: :test, runtime: false},
      {:ex_doc, "~> 0.26", only: :docs, runtime: false}
    ]
  end

  defp description do
    "In-memory key-value store with subscriptions"
  end

  defp package do
    [
      files: [
        "CHANGELOG.md",
        "lib",
        "LICENSES/*",
        "mix.exs",
        "NOTICE",
        "README.md",
        "REUSE.toml"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/nerves-project/property_table"
      }
    ]
  end

  defp dialyzer() do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
      list_unused_filters: true,
      plt_file: {:no_warn, "_build/plts/dialyzer.plt"}
    ]
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
