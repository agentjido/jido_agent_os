defmodule Jido.AgentOS do
  @moduledoc """
  Public API for embeddable, kernel-scoped Jido AgentOS kernels.

  `Jido.AgentOS` is the kernel host layer. In a Phoenix application, the common
  pattern is:

      children = [
        {MyApp.AgentOS, []},
        MyAppWeb.Endpoint
      ]

  `MyApp.AgentOS` plays the same role as `MyApp.Repo`: it is the long-lived
  kernel boundary that the rest of the application supervises and calls.

  Glossary:

  - kernel: the named `MyApp.AgentOS` wrapper and its shared services
  - pod: the durable Jido pod definition and runtime unit that a kernel runs

  A recommended project layout looks like:

      lib/my_app/agent_os.ex
      lib/my_app/agent_os/pods/default.ex
      lib/my_app/agent_os/agents/calculator.ex
      lib/my_app/agent_os/actions/add.ex
  """

  alias Jido.AgentOS.{KernelRegistry, Naming, Persistence}

  @default_kernel :jido_agent_os

  @type kernel_ref :: atom() | String.t()
  @type pod_ref :: atom() | String.t()
  @type node_ref :: atom() | String.t()
  @type wrapper_defaults :: keyword() | kernel_ref() | nil
  @type pod_definition_ref :: module() | nil
  @type persistence_ref :: Persistence.t() | Persistence.storage_tuple() | keyword() | nil

  @doc """
  Defines a host wrapper module around `Jido.AgentOS`.
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app)
    default_name = Keyword.get(opts, :name)
    default_pod = Keyword.get(opts, :pod)

    default_opts =
      []
      |> maybe_put(:name, default_name)
      |> maybe_put(:pod, default_pod)

    quote bind_quoted: [otp_app: otp_app, default_opts: default_opts] do
      @jido_agent_os_otp_app otp_app
      @jido_agent_os_default_opts default_opts

      @doc """
      Returns the merged kernel configuration for this wrapper.
      """
      @spec config(keyword()) :: keyword()
      def config(overrides \\ []) do
        Jido.AgentOS.resolve_kernel_opts(
          __MODULE__,
          @jido_agent_os_otp_app,
          @jido_agent_os_default_opts,
          overrides
        )
      end

      defoverridable config: 1

      @spec name() :: Jido.AgentOS.kernel_ref()
      def name do
        config()
        |> Jido.AgentOS.kernel_name_from_opts()
      end

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts \\ []) when is_list(opts) do
        config(opts)
        |> Jido.AgentOS.child_spec()
      end

      @spec start_link(keyword()) :: Supervisor.on_start()
      def start_link(opts \\ []) when is_list(opts) do
        config(opts)
        |> Jido.AgentOS.start_link()
      end

      @spec ensure_pod(Jido.AgentOS.pod_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
      def ensure_pod(pod_id, opts \\ []) when is_list(opts) do
        Jido.AgentOS.ensure_pod(name(), pod_id, opts)
      end

      @spec pod_pid(Jido.AgentOS.pod_ref()) :: {:ok, pid()} | {:error, term()}
      def pod_pid(pod_id), do: Jido.AgentOS.pod_pid(name(), pod_id)

      @spec pod_snapshot(Jido.AgentOS.pod_ref()) :: {:ok, map()} | {:error, term()}
      def pod_snapshot(pod_id), do: Jido.AgentOS.pod_snapshot(name(), pod_id)

      @spec reconcile_pod(Jido.AgentOS.pod_ref(), keyword()) :: {:ok, map()} | {:error, term()}
      def reconcile_pod(pod_id, opts \\ []) when is_list(opts) do
        Jido.AgentOS.reconcile_pod(name(), pod_id, opts)
      end

      @spec ensure_node(Jido.AgentOS.pod_ref(), Jido.AgentOS.node_ref(), keyword()) ::
              {:ok, pid()} | {:error, term()}
      def ensure_node(pod_id, node_name, opts \\ []) when is_list(opts) do
        Jido.AgentOS.ensure_node(name(), pod_id, node_name, opts)
      end

      @spec mutate_pod(Jido.AgentOS.pod_ref(), [term()], keyword()) ::
              {:ok, map()} | {:error, term()}
      def mutate_pod(pod_id, ops, opts \\ []) when is_list(opts) do
        Jido.AgentOS.mutate_pod(name(), pod_id, ops, opts)
      end

      @spec list_pods() :: [String.t()]
      def list_pods, do: Jido.AgentOS.list_pods(name())

      @spec kernel_status() :: map()
      def kernel_status, do: Jido.AgentOS.kernel_status(name())

      @spec pod() :: module() | nil
      def pod, do: Jido.AgentOS.kernel_pod(config())

      @spec persistence() :: Jido.AgentOS.Persistence.t() | nil
      def persistence, do: Jido.AgentOS.kernel_persistence(config())

      @spec storage() :: Jido.AgentOS.Persistence.storage_tuple() | nil
      def storage, do: Jido.AgentOS.kernel_storage(config())
    end
  end

  @doc """
  Returns the root supervisor module for AgentOS kernels.

  ## Examples

      iex> Jido.AgentOS.root_supervisor()
      Jido.AgentOS.Supervisor

  """
  @spec root_supervisor() :: module()
  def root_supervisor, do: Jido.AgentOS.Supervisor

  @doc """
  Builds the normalized kernel configuration used by the supervisor tree.
  """
  @spec build_kernel_config(keyword()) :: map()
  def build_kernel_config(opts) when is_list(opts) do
    kernel_name = kernel_name_from_opts(opts)
    pod = kernel_pod(opts)
    persistence = kernel_persistence(opts)

    %{
      kernel_name: kernel_name,
      naming: Naming.new(kernel_name),
      jido: Naming.new(kernel_name) |> Naming.kernel_jido_instance(),
      pod: pod,
      persistence: persistence,
      storage: Persistence.storage(persistence)
    }
  end

  @doc """
  Returns the kernel name that will be used for a kernel child spec.
  """
  @spec kernel_name_from_opts(keyword()) :: kernel_ref()
  def kernel_name_from_opts(opts) when is_list(opts) do
    opts
    |> Keyword.get(:name, @default_kernel)
    |> normalize_kernel_name()
  end

  @doc """
  Builds a child spec for an embeddable kernel.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    kernel_name = kernel_name_from_opts(opts)

    %{
      id: Keyword.get(opts, :id, {__MODULE__, kernel_name}),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts a named kernel.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts), do: Jido.AgentOS.Supervisor.start_link(opts)

  @doc """
  Ensures a pod exists in the default kernel.
  """
  @spec ensure_pod(pod_ref()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(pod_id), do: ensure_pod(@default_kernel, pod_id, [])

  @doc """
  Ensures a pod exists.

  When called as `ensure_pod(pod_id, opts)`, the default kernel is used.
  When called as `ensure_pod(kernel, pod_id)`, the given kernel is used.
  """
  @spec ensure_pod(pod_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(pod_id, opts) when is_list(opts) do
    ensure_pod(@default_kernel, pod_id, opts)
  end

  @spec ensure_pod(kernel_ref(), pod_ref()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(kernel, pod_id), do: ensure_pod(kernel, pod_id, [])

  @doc """
  Ensures a pod exists in the given kernel with extra options.
  """
  @spec ensure_pod(kernel_ref(), pod_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(kernel, pod_id, opts) when is_list(opts) do
    KernelRegistry.ensure_pod(naming(kernel), pod_id, opts)
  end

  @doc """
  Looks up a pod process in the default kernel.
  """
  @spec pod_pid(pod_ref()) :: {:ok, pid()} | {:error, term()}
  def pod_pid(pod_id), do: pod_pid(@default_kernel, pod_id)

  @doc """
  Looks up a pod process in the given kernel.
  """
  @spec pod_pid(kernel_ref(), pod_ref()) :: {:ok, pid()} | {:error, term()}
  def pod_pid(kernel, pod_id) do
    KernelRegistry.pod_pid(naming(kernel), pod_id)
  end

  @doc """
  Returns a snapshot of a started pod in the default kernel.
  """
  @spec pod_snapshot(pod_ref()) :: {:ok, map()} | {:error, term()}
  def pod_snapshot(pod_id), do: pod_snapshot(@default_kernel, pod_id)

  @doc """
  Returns a snapshot of a started pod in the given kernel.
  """
  @spec pod_snapshot(kernel_ref(), pod_ref()) :: {:ok, map()} | {:error, term()}
  def pod_snapshot(kernel, pod_id) do
    naming = naming(kernel)
    details = KernelRegistry.kernel_details(naming)

    with {:ok, pid} <- pod_pid(kernel, pod_id),
         {:ok, topology} <- Jido.Pod.fetch_topology(pid),
         {:ok, node_snapshots} <- Jido.Pod.nodes(pid) do
      {:ok,
       %{
         kernel_name: Naming.kernel_name(naming),
         pod_id: Naming.pod_id(pod_id),
         pod: Map.get(details, :pod),
         topology_name: topology.name,
         nodes: topology.nodes |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
         node_snapshots: serialize_node_snapshots(node_snapshots),
         pid: pid
       }}
    end
  end

  @doc """
  Reconciles eager nodes for a started pod in the default kernel.
  """
  @spec reconcile_pod(pod_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def reconcile_pod(pod_id, opts \\ []) when is_list(opts) do
    reconcile_pod(@default_kernel, pod_id, opts)
  end

  @doc """
  Reconciles eager nodes for a started pod in the given kernel.
  """
  @spec reconcile_pod(kernel_ref(), pod_ref(), keyword()) :: {:ok, map()} | {:error, term()}
  def reconcile_pod(kernel, pod_id, opts) when is_list(opts) do
    with {:ok, pid} <- pod_pid(kernel, pod_id),
         {:ok, report} <- Jido.Pod.reconcile(pid, opts) do
      {:ok, serialize_reconcile_report(report)}
    end
  end

  @doc """
  Ensures a named node is running inside a started pod in the default kernel.
  """
  @spec ensure_node(pod_ref(), node_ref(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_node(pod_id, node_name, opts \\ []) when is_list(opts) do
    ensure_node(@default_kernel, pod_id, node_name, opts)
  end

  @doc """
  Ensures a named node is running inside a started pod in the given kernel.
  """
  @spec ensure_node(kernel_ref(), pod_ref(), node_ref(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_node(kernel, pod_id, node_name, opts) when is_list(opts) do
    with {:ok, pid} <- pod_pid(kernel, pod_id) do
      Jido.Pod.ensure_node(pid, node_name, opts)
    end
  end

  @doc """
  Applies live topology mutations to a started pod in the default kernel.
  """
  @spec mutate_pod(pod_ref(), [term()], keyword()) :: {:ok, map()} | {:error, term()}
  def mutate_pod(pod_id, ops, opts \\ []) when is_list(ops) and is_list(opts) do
    mutate_pod(@default_kernel, pod_id, ops, opts)
  end

  @doc """
  Applies live topology mutations to a started pod in the given kernel.
  """
  @spec mutate_pod(kernel_ref(), pod_ref(), [term()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def mutate_pod(kernel, pod_id, ops, opts) when is_list(ops) and is_list(opts) do
    with {:ok, pid} <- pod_pid(kernel, pod_id) do
      case Jido.Pod.mutate(pid, ops, opts) do
        {:ok, report} -> {:ok, serialize_mutation_report(report)}
        {:error, report} when is_map(report) -> {:error, serialize_mutation_report(report)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists started pods for the default kernel.
  """
  @spec list_pods() :: [String.t()]
  def list_pods, do: list_pods(@default_kernel)

  @doc """
  Lists started pods for the given kernel.
  """
  @spec list_pods(kernel_ref()) :: [String.t()]
  def list_pods(kernel) do
    KernelRegistry.list_pods(naming(kernel))
  end

  @doc """
  Returns lightweight kernel status for host applications.
  """
  @spec kernel_status() :: map()
  def kernel_status, do: kernel_status(@default_kernel)

  @doc """
  Returns lightweight kernel status for the given kernel.
  """
  @spec kernel_status(kernel_ref()) :: map()
  def kernel_status(kernel) do
    naming = naming(kernel)
    details = KernelRegistry.kernel_details(naming)

    %{
      kernel_name: Naming.kernel_name(naming),
      supervisor: GenServer.whereis(Naming.via_kernel_supervisor(naming)),
      pod: Map.get(details, :pod),
      persistence: Map.get(details, :persistence),
      pods: list_pods(kernel)
    }
  end

  @doc false
  @spec wrapper_name(module(), atom() | nil, wrapper_defaults()) :: kernel_ref()
  def wrapper_name(module, otp_app, default_name) do
    resolve_kernel_opts(module, otp_app, default_name, [])
    |> kernel_name_from_opts()
  end

  @doc false
  @spec resolve_kernel_opts(module(), atom() | nil, wrapper_defaults(), keyword()) :: keyword()
  def resolve_kernel_opts(module, otp_app, default_name, opts) when is_list(opts) do
    base = normalize_wrapper_defaults(default_name)

    shared = if otp_app, do: Application.get_env(otp_app, __MODULE__, []), else: []
    wrapper = if otp_app, do: Application.get_env(otp_app, module, []), else: []

    base
    |> merge_kernel_opts(shared)
    |> merge_kernel_opts(wrapper)
    |> merge_kernel_opts(opts)
  end

  @doc false
  @spec wrapper_opts(module(), atom() | nil, wrapper_defaults(), keyword()) :: keyword()
  def wrapper_opts(module, otp_app, default_name, opts) when is_list(opts) do
    resolve_kernel_opts(module, otp_app, default_name, opts)
  end

  @doc false
  @spec kernel_pod(keyword()) :: pod_definition_ref()
  def kernel_pod(opts) when is_list(opts) do
    opts
    |> Keyword.get(:pod)
    |> resolve_pod_definition!()
  end

  @doc false
  @spec kernel_persistence(keyword()) :: Persistence.t() | nil
  def kernel_persistence(opts) when is_list(opts) do
    opts
    |> Keyword.get(:persistence)
    |> Persistence.resolve!()
  end

  @doc false
  @spec kernel_storage(keyword()) :: Persistence.storage_tuple() | nil
  def kernel_storage(opts) when is_list(opts) do
    opts
    |> kernel_persistence()
    |> Persistence.storage()
  end

  @doc false
  @spec merge_kernel_opts(keyword(), keyword()) :: keyword()
  def merge_kernel_opts(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      Keyword.merge(left, right, fn key, left_value, right_value ->
        merge_kernel_value(key, left_value, right_value)
      end)
    else
      right
    end
  end

  @spec naming(kernel_ref()) :: Naming.t()
  def naming(kernel), do: Naming.new(kernel)

  defp resolve_pod_definition!(nil), do: nil

  defp resolve_pod_definition!(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _loaded} ->
        cond do
          function_exported?(module, :pod?, 0) and module.pod?() and
              function_exported?(module, :topology, 0) ->
            module

          true ->
            raise ArgumentError,
                  "AgentOS pod must be a Jido.Pod module with pod?/0 and topology/0: #{inspect(module)}"
        end

      {:error, reason} ->
        raise ArgumentError,
              "unable to load AgentOS pod #{inspect(module)}: #{inspect(reason)}"
    end
  end

  defp resolve_pod_definition!(other) do
    raise ArgumentError, "invalid AgentOS pod definition: #{inspect(other)}"
  end

  defp normalize_wrapper_defaults(defaults) when is_list(defaults), do: defaults
  defp normalize_wrapper_defaults(nil), do: []
  defp normalize_wrapper_defaults(value), do: [name: value]

  defp merge_kernel_value(_key, left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn key, left_value, right_value ->
      merge_kernel_value(key, left_value, right_value)
    end)
  end

  defp merge_kernel_value(_key, left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      merge_kernel_opts(left, right)
    else
      right
    end
  end

  defp merge_kernel_value(_key, _left, right), do: right

  defp normalize_kernel_name(value) when is_atom(value), do: value

  defp normalize_kernel_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @default_kernel
      normalized -> normalized
    end
  end

  defp normalize_kernel_name(nil), do: @default_kernel

  defp normalize_kernel_name(value) do
    value
    |> to_string()
    |> normalize_kernel_name()
  end

  defp serialize_node_snapshots(node_snapshots) do
    node_snapshots
    |> Enum.sort_by(fn {name, _snapshot} -> to_string(name) end)
    |> Enum.map(fn {name, snapshot} ->
      %{
        name: to_string(name),
        module: inspect(snapshot.node.module),
        manager: to_string(snapshot.node.manager),
        activation: to_string(snapshot.node.activation),
        status: to_string(snapshot.status),
        owner: snapshot.owner && to_string(snapshot.owner),
        pid: snapshot.pid && inspect(snapshot.pid),
        running_pid: snapshot.running_pid && inspect(snapshot.running_pid),
        adopted?: snapshot.adopted?
      }
    end)
  end

  defp serialize_reconcile_report(report) when is_map(report) do
    %{
      requested: serialize_name_list(Map.get(report, :requested, [])),
      waves: serialize_name_waves(Map.get(report, :waves, [])),
      nodes:
        report
        |> Map.get(:nodes, %{})
        |> Enum.map(fn {name, node_report} ->
          {to_string(name),
           %{
             pid: inspect(node_report.pid),
             source: to_string(node_report.source),
             owner: node_report.owner && to_string(node_report.owner),
             parent:
               case node_report.parent do
                 value when is_atom(value) -> to_string(value)
                 value when is_binary(value) -> value
                 nil -> nil
                 value -> inspect(value)
               end
           }}
        end)
        |> Map.new(),
      failures:
        report
        |> Map.get(:failures, %{})
        |> Enum.map(fn {name, reason} -> {to_string(name), inspect(reason)} end)
        |> Map.new(),
      completed: serialize_name_list(Map.get(report, :completed, [])),
      failed: serialize_name_list(Map.get(report, :failed, [])),
      pending: serialize_name_list(Map.get(report, :pending, []))
    }
  end

  defp serialize_mutation_report(report) when is_map(report) do
    status = Map.get(report, :status)

    %{
      mutation_id: Map.get(report, :mutation_id),
      status: status && to_string(status),
      topology_version: Map.get(report, :topology_version),
      requested_ops: Enum.map(Map.get(report, :requested_ops, []), &inspect/1),
      added: serialize_name_list(Map.get(report, :added, [])),
      removed: serialize_name_list(Map.get(report, :removed, [])),
      started: serialize_name_list(Map.get(report, :started, [])),
      stopped: serialize_name_list(Map.get(report, :stopped, [])),
      failures:
        report
        |> Map.get(:failures, %{})
        |> Enum.map(fn {name, reason} -> {to_string(name), inspect(reason)} end)
        |> Map.new()
    }
  end

  defp serialize_name_waves(waves) do
    Enum.map(waves, &serialize_name_list/1)
  end

  defp serialize_name_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, _key, []), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
