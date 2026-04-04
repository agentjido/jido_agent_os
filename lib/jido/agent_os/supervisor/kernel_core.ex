defmodule Jido.AgentOS.Supervisor.KernelCore do
  @moduledoc false

  use Supervisor

  alias Jido.Agent.InstanceManager
  alias Jido.AgentOS.ManagerSupervisor
  alias Jido.AgentOS.Naming

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    kernel = Keyword.fetch!(opts, :kernel)
    name = Keyword.get(opts, :name, Naming.via_kernel_core(kernel.naming))
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    kernel = Keyword.fetch!(opts, :kernel)
    naming = kernel.naming

    case ManagerSupervisor.ensure_managers(kernel.pod, kernel.storage, kernel.jido, kernel.naming) do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "unable to boot AgentOS pod managers: #{inspect(reason)}"
    end

    children =
      [
        {Jido, name: kernel.jido},
        {Task.Supervisor, name: Naming.via_kernel_task_supervisor(naming)},
        {InstanceManager,
         name: Naming.kernel_pod_manager(naming),
         agent: kernel.pod,
         storage: kernel.storage,
         jido: kernel.jido},
        {Jido.AgentOS.KernelRegistry,
         name: Naming.via_kernel_registry(naming),
         kernel: kernel,
         pod_manager: Naming.kernel_pod_manager(naming)}
      ]
      |> Enum.reject(fn
        {InstanceManager, manager_opts} -> is_nil(Keyword.get(manager_opts, :agent))
        _child -> false
      end)

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
