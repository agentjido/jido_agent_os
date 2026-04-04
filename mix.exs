defmodule Jido.AgentOS.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_agent_os,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.AgentOS.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, github: "agentjido/jido", branch: "main", override: true},
      {:jido_ai, github: "agentjido/jido_ai", branch: "main"}
    ]
  end
end
