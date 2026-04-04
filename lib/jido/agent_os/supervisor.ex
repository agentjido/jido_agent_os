defmodule Jido.AgentOS.Supervisor do
  @moduledoc """
  Root supervisor for a named Jido AgentOS kernel.
  """

  use Supervisor

  alias Jido.AgentOS.Naming
  alias Jido.AgentOS.Supervisor.KernelCore

  @doc """
  Starts a named kernel supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    naming = opts |> Jido.AgentOS.build_kernel_config() |> Map.fetch!(:naming)
    supervisor_name = Keyword.get(opts, :supervisor_name, Naming.via_kernel_supervisor(naming))

    Supervisor.start_link(__MODULE__, opts, name: supervisor_name)
  end

  @impl true
  def init(opts) do
    kernel = Jido.AgentOS.build_kernel_config(opts)

    children = [
      {KernelCore, kernel: kernel, name: Naming.via_kernel_core(kernel.naming)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
