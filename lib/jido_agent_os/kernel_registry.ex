defmodule Jido.AgentOS.KernelRegistry do
  @moduledoc false

  use GenServer

  alias Jido.Agent.InstanceManager
  alias Jido.AgentOS.{Naming, Persistence, Pod}
  alias Jido.Pod, as: JidoPod

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @spec ensure_pod(Naming.t() | GenServer.server(), term(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_pod(server_or_naming, pod_id, opts \\ [])

  def ensure_pod(%Naming{} = naming, pod_id, opts) when is_list(opts) do
    ensure_pod(Naming.via_kernel_registry(naming), pod_id, opts)
  end

  def ensure_pod(registry, pod_id, opts) when is_list(opts) do
    safe_call(registry, {:ensure_pod, Naming.pod_id(pod_id), opts})
  end

  @spec pod_pid(Naming.t() | GenServer.server(), term()) :: {:ok, pid()} | {:error, term()}
  def pod_pid(%Naming{} = naming, pod_id) do
    pod_pid(Naming.via_kernel_registry(naming), pod_id)
  end

  def pod_pid(registry, pod_id) do
    safe_call(registry, {:pod_pid, Naming.pod_id(pod_id)})
  end

  @spec list_pods(Naming.t() | GenServer.server()) :: [String.t()]
  def list_pods(%Naming{} = naming), do: list_pods(Naming.via_kernel_registry(naming))

  def list_pods(registry) do
    case safe_call(registry, :list_pods) do
      {:ok, pods} -> pods
      {:error, _reason} -> []
    end
  end

  @spec kernel_details(Naming.t() | GenServer.server()) :: map()
  def kernel_details(%Naming{} = naming), do: kernel_details(Naming.via_kernel_registry(naming))

  def kernel_details(registry) do
    case safe_call(registry, :kernel_details) do
      {:ok, details} -> details
      {:error, _reason} -> %{pod: nil}
    end
  end

  @impl true
  def init(opts) do
    kernel = Keyword.fetch!(opts, :kernel)

    {:ok,
     %{
       kernel: kernel,
       naming: kernel.naming,
       pod_manager: Keyword.get(opts, :pod_manager)
     }}
  end

  @impl true
  def handle_call({:ensure_pod, pod_id, opts}, _from, state) do
    {:reply, ensure_pod_internal(state, pod_id, opts), state}
  end

  def handle_call({:pod_pid, pod_id}, _from, state) do
    {:reply, pod_pid_internal(state, pod_id), state}
  end

  def handle_call(:list_pods, _from, state) do
    {:reply, {:ok, list_pods_internal(state)}, state}
  end

  def handle_call(:kernel_details, _from, state) do
    details = %{
      pod: Pod.summary(state.kernel.pod),
      persistence: Persistence.summary(state.kernel.persistence)
    }

    {:reply, {:ok, details}, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp ensure_pod_internal(%{kernel: %{pod: nil}}, _pod_id, _opts),
    do: {:error, :pod_not_configured}

  defp ensure_pod_internal(%{pod_manager: nil}, _pod_id, _opts),
    do: {:error, :pod_manager_not_started}

  defp ensure_pod_internal(state, pod_id, opts) do
    get_opts = Pod.instance_opts(state.kernel.pod, state.naming, opts)

    state.naming
    |> Naming.runtime_pod_key(pod_id)
    |> then(&JidoPod.get(state.pod_manager, &1, get_opts))
    |> maybe_retry_reconcile()
  end

  defp pod_pid_internal(%{kernel: %{pod: nil}}, _pod_id), do: {:error, :pod_not_configured}
  defp pod_pid_internal(%{pod_manager: nil}, _pod_id), do: {:error, :pod_manager_not_started}

  defp pod_pid_internal(state, pod_id) do
    case InstanceManager.lookup(state.pod_manager, Naming.runtime_pod_key(state.naming, pod_id)) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, :pod_not_found}
    end
  end

  defp list_pods_internal(%{kernel: %{pod: nil}}), do: []
  defp list_pods_internal(%{pod_manager: nil}), do: []

  defp list_pods_internal(state) do
    state.pod_manager
    |> InstanceManager.stats()
    |> Map.fetch!(:keys)
    |> Enum.map(&Naming.user_pod_id/1)
    |> Enum.sort()
    |> Enum.uniq()
  rescue
    ArgumentError -> []
    RuntimeError -> []
  end

  defp safe_call(server, message) do
    GenServer.call(server, message)
  catch
    :exit, {:noproc, _} -> {:error, :kernel_not_started}
    :exit, {:normal, _} -> {:error, :kernel_not_started}
  end

  defp maybe_retry_reconcile({:error, %{stage: :reconcile, pod: pod_pid}} = result)
       when is_pid(pod_pid) do
    case JidoPod.reconcile(pod_pid) do
      {:ok, _report} -> {:ok, pod_pid}
      {:error, _report} -> result
    end
  end

  defp maybe_retry_reconcile(result), do: result
end
