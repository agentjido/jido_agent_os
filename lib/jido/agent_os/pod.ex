defmodule Jido.AgentOS.Pod do
  @moduledoc """
  Pod definition helper for AgentOS kernels.

  AgentOS kernels run pods directly. `Jido.AgentOS.Pod` keeps topology in the
  pod module and derives logical manager definitions for kernel boot.

  Standard `Jido.Pod` options such as `plugins:` and `default_plugins:` pass
  through unchanged, so pod behavior should extend through normal `Jido.Plugin`
  modules instead of AgentOS-specific extension abstractions.

  A typical host-app pod looks like:

      defmodule MyApp.AgentOS.Pods.RepoPod do
        use Jido.AgentOS.Pod,
          name: "repo_pod",
          topology: %{
            repo_state: %{agent: MyApp.AgentOS.Agents.RepoState, manager: :repo_state, activation: :eager},
            planner: %{agent: MyApp.AgentOS.Agents.Planner, manager: :planning, activation: :lazy}
          }
      end

  Recommended placement inside a host app:

      lib/my_app/agent_os/pods/repo_pod.ex
  """

  alias Jido.AgentServer
  alias Jido.AgentOS.Naming
  alias Jido.Pod, as: JidoPod
  alias Jido.Pod.Definition
  alias Jido.Pod.Plugin, as: PodPlugin
  alias Jido.Pod.Topology
  alias Jido.Pod.Topology.Node

  @type manager_spec :: %{
          logical_name: String.t(),
          name: atom(),
          module: module(),
          kind: :agent | :pod
        }

  @doc """
  Defines an AgentOS pod module.
  """
  defmacro __using__(opts) do
    definition = resolve_definition!(opts, __CALLER__.module, __CALLER__)

    quote location: :keep do
      use Jido.Pod, unquote(Macro.escape(definition.pod_opts))

      @agent_os_manager_specs unquote(Macro.escape(definition.manager_specs))

      @doc "Returns logical manager definitions derived from the pod topology."
      @spec manager_specs() :: [map()]
      def manager_specs, do: @agent_os_manager_specs
    end
  end

  @doc """
  Returns a JSON-friendly summary of a pod module or running pod.
  """
  @spec summary(module() | AgentServer.server() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(source) do
    module = source_module(source)
    {:ok, topology} = JidoPod.fetch_topology(source)
    manager_specs = manager_specs(source, topology, module)

    %{
      module: format_module(module),
      name: topology.name,
      topology_name: topology.name,
      nodes: topology.nodes |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      managers: Enum.map(manager_specs, &summarize_manager/1)
    }
  end

  @doc """
  Returns logical manager specs for an AgentOS pod module.
  """
  @spec manager_specs(module()) :: [manager_spec()]
  def manager_specs(module) when is_atom(module) do
    cond do
      function_exported?(module, :manager_specs, 0) ->
        module.manager_specs()

      function_exported?(module, :topology, 0) ->
        derive_manager_specs(module.topology())

      true ->
        []
    end
  end

  @doc """
  Returns kernel-scoped runtime manager specs for a pod module.
  """
  @spec runtime_manager_specs(module(), Naming.t() | Jido.AgentOS.kernel_ref()) :: [
          manager_spec()
        ]
  def runtime_manager_specs(module, %Naming{} = naming) when is_atom(module) do
    module
    |> fetch_module_topology!()
    |> scope_runtime_topology(module, naming)
    |> elem(1)
  end

  def runtime_manager_specs(module, kernel) when is_atom(module) do
    runtime_manager_specs(module, Naming.new(kernel))
  end

  @doc """
  Returns the kernel-scoped runtime manager atom for a pod module and logical manager key.
  """
  @spec manager_atom(Naming.t() | Jido.AgentOS.kernel_ref(), module(), atom() | String.t()) ::
          atom()
  def manager_atom(%Naming{} = naming, pod_module, logical_name) when is_atom(pod_module) do
    parts =
      Module.split(pod_module)
      |> Enum.map(&Macro.underscore/1)
      |> Kernel.++([Naming.kernel_name(naming), normalize_manager_name(logical_name)])

    Naming.manager_atom(parts)
  end

  def manager_atom(kernel, pod_module, logical_name) do
    manager_atom(Naming.new(kernel), pod_module, logical_name)
  end

  @doc """
  Returns a kernel-scoped topology for a pod module.
  """
  @spec scoped_topology(module(), Naming.t() | Jido.AgentOS.kernel_ref()) :: Topology.t()
  def scoped_topology(module, %Naming{} = naming) when is_atom(module) do
    module
    |> fetch_module_topology!()
    |> scope_runtime_topology(module, naming)
    |> elem(0)
  end

  def scoped_topology(module, kernel) when is_atom(module) do
    scoped_topology(module, Naming.new(kernel))
  end

  @doc """
  Builds fresh pod startup options for the given kernel by injecting a scoped topology.
  """
  @spec instance_opts(module() | nil, Naming.t() | Jido.AgentOS.kernel_ref(), keyword()) ::
          keyword()
  def instance_opts(nil, _kernel, opts) when is_list(opts), do: opts

  def instance_opts(module, %Naming{} = naming, opts) when is_atom(module) and is_list(opts) do
    topology = scoped_topology(module, naming)

    initial_state =
      opts
      |> Keyword.get(:initial_state, %{})
      |> deep_merge(%{PodPlugin.state_key_atom() => %{topology: topology}})

    Keyword.put(opts, :initial_state, initial_state)
  end

  def instance_opts(module, kernel, opts) when is_atom(module) and is_list(opts) do
    instance_opts(module, Naming.new(kernel), opts)
  end

  @doc false
  @spec resolve_definition!(Macro.t(), module(), Macro.Env.t()) :: map()
  def resolve_definition!(opts, _module, caller_env) do
    resolved_opts =
      opts
      |> Definition.expand_aliases_in_ast(caller_env)
      |> Code.eval_quoted([], caller_env)
      |> elem(0)

    name = Keyword.fetch!(resolved_opts, :name)

    topology =
      Definition.resolve_topology!(name, Keyword.get(resolved_opts, :topology, %{}), caller_env)

    {normalized_topology, manager_specs} = normalize_topology_managers(topology, caller_env)

    %{
      pod_opts: Keyword.put(resolved_opts, :topology, normalized_topology),
      manager_specs: manager_specs
    }
  end

  defp normalize_topology_managers(%Topology{} = topology, caller_env) do
    {nodes, specs} =
      Enum.reduce(topology.nodes, {%{}, %{}}, fn {name, %Node{} = node}, {nodes, specs} ->
        logical_name = normalize_manager_name(node.manager)

        next_specs =
          case Map.get(specs, node.manager) do
            nil ->
              Map.put(specs, node.manager, %{
                logical_name: logical_name,
                name: node.manager,
                module: node.module,
                kind: node.kind
              })

            %{module: actual_module} ->
              if actual_module == node.module do
                specs
              else
                raise CompileError,
                  description:
                    "Pod manager #{inspect(logical_name)} is used for multiple modules: " <>
                      "#{inspect(actual_module)} and #{inspect(node.module)}",
                  file: caller_env.file,
                  line: caller_env.line
              end
          end

        {Map.put(nodes, name, node), next_specs}
      end)

    {%{topology | nodes: nodes}, specs |> Map.values() |> Enum.sort_by(&Atom.to_string(&1.name))}
  end

  defp scope_runtime_topology(%Topology{} = topology, module, %Naming{} = naming) do
    {nodes, specs} =
      Enum.reduce(topology.nodes, {%{}, %{}}, fn {name, %Node{} = node}, {nodes, specs} ->
        logical_name = normalize_manager_name(node.manager)
        runtime_name = manager_atom(naming, module, logical_name)

        next_specs =
          Map.put_new(specs, runtime_name, %{
            logical_name: logical_name,
            name: runtime_name,
            module: node.module,
            kind: node.kind
          })

        {Map.put(nodes, name, %{node | manager: runtime_name}), next_specs}
      end)

    {%{topology | nodes: nodes}, specs |> Map.values() |> Enum.sort_by(&Atom.to_string(&1.name))}
  end

  defp manager_specs(source, topology, module) do
    cond do
      is_atom(source) and is_atom(module) and function_exported?(module, :manager_specs, 0) ->
        module.manager_specs()

      true ->
        derive_manager_specs(topology)
    end
  end

  defp derive_manager_specs(%Topology{} = topology) do
    topology.nodes
    |> Enum.reduce(%{}, fn {_name, %Node{} = node}, acc ->
      Map.put_new(acc, node.manager, %{
        logical_name: normalize_manager_name(node.manager),
        name: node.manager,
        module: node.module,
        kind: node.kind
      })
    end)
    |> Map.values()
    |> Enum.sort_by(&Atom.to_string(&1.name))
  end

  defp fetch_module_topology!(module) do
    if function_exported?(module, :topology, 0) do
      module.topology()
    else
      raise ArgumentError, "#{inspect(module)} does not export topology/0"
    end
  end

  defp summarize_manager(spec) do
    %{
      logical_name: spec.logical_name,
      runtime_name: Atom.to_string(spec.name),
      module: format_module(spec.module),
      kind: spec.kind |> to_string()
    }
  end

  defp source_module(source) when is_atom(source) do
    if function_exported?(source, :topology, 0), do: source, else: nil
  end

  defp source_module(source) do
    case AgentServer.state(source) do
      {:ok, state} -> state.agent_module
      _other -> nil
    end
  end

  defp normalize_manager_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_manager_name(value) when is_binary(value), do: value
  defp normalize_manager_name(value), do: to_string(value)

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)
  defp format_module(other), do: inspect(other)

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp deep_merge(_left, right), do: right
end
