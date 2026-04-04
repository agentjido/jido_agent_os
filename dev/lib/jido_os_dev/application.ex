defmodule JidoOSDev.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        JidoOSDev.Repo,
        {Phoenix.PubSub, name: JidoOSDev.PubSub},
        JidoOSDev.ObservabilityLog,
        {JidoOSDevAgents, []},
        JidoOSDevWeb.Endpoint
      ]

    Supervisor.start_link(children, strategy: :one_for_one, name: JidoOSDev.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    JidoOSDevWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
