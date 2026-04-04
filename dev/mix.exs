defmodule JidoOSDev.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_os_dev,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {JidoOSDev.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_agent_os, path: ".."},
      {:jido, github: "agentjido/jido", branch: "main", override: true},
      {:jido_ai, github: "agentjido/jido_ai", branch: "main"},
      {:jido_ecto, github: "agentjido/jido_ecto", branch: "main"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:git_cli, "~> 0.3.0"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.2"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
