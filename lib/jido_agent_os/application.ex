defmodule Jido.AgentOS.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Jido.AgentOS.ProcessRegistry},
      Jido.AgentOS.ManagerSupervisor
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: Jido.AgentOS.Application.Supervisor
    )
  end
end
