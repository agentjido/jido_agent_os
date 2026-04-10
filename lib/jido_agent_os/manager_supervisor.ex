defmodule Jido.AgentOS.ManagerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Jido.Agent.InstanceManager
  alias Jido.AgentOS.Pod

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec ensure_managers(module() | nil, keyword() | nil, atom() | nil, term()) ::
          :ok | {:error, term()}
  def ensure_managers(nil, _storage, _jido, _kernel), do: :ok

  def ensure_managers(pod_module, storage, jido, kernel) when is_atom(pod_module) do
    pod_module
    |> Pod.runtime_manager_specs(kernel)
    |> Enum.reduce_while(:ok, fn spec, :ok ->
      case ensure_manager(spec.name, spec.module, storage, jido) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec ensure_manager(atom(), module(), keyword() | nil, atom() | nil) :: :ok | {:error, term()}
  def ensure_manager(name, agent_module, storage, jido)
      when is_atom(name) and is_atom(agent_module) do
    case InstanceManager.agent_module(name) do
      {:ok, ^agent_module} ->
        :ok

      {:ok, actual_module} ->
        {:error,
         Jido.Error.validation_error(
           "AgentOS manager name is already bound to a different module.",
           details: %{name: name, expected: agent_module, actual: actual_module}
         )}

      {:error, :not_found} ->
        child_spec =
          InstanceManager.child_spec(
            name: name,
            agent: agent_module,
            storage: storage,
            jido: jido
          )

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            ensure_manager(name, agent_module, storage, jido)

          {:error, {:already_present, _child}} ->
            ensure_manager(name, agent_module, storage, jido)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
