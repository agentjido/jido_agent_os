defmodule Jido.AgentOS.Naming do
  @moduledoc false

  @default_kernel :jido_agent_os

  defstruct [:kernel_name]

  @type kernel_name :: atom() | String.t()
  @type t :: %__MODULE__{kernel_name: kernel_name()}

  @spec new(term()) :: t()
  def new(kernel) do
    %__MODULE__{kernel_name: normalize_kernel(kernel)}
  end

  @spec default() :: t()
  def default, do: new(@default_kernel)

  @spec kernel_name(t()) :: kernel_name()
  def kernel_name(%__MODULE__{kernel_name: kernel_name}), do: kernel_name

  @spec pod_id(term()) :: String.t()
  def pod_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "default"
      normalized -> normalized
    end
  end

  def pod_id(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> pod_id()
  end

  def pod_id(value) do
    value
    |> to_string()
    |> pod_id()
  end

  @spec via_kernel_supervisor(t()) :: {:via, Registry, {atom(), tuple()}}
  def via_kernel_supervisor(%__MODULE__{} = naming),
    do: via(naming, {:kernel_supervisor, kernel_name(naming)})

  @spec via_kernel_core(t()) :: {:via, Registry, {atom(), tuple()}}
  def via_kernel_core(%__MODULE__{} = naming),
    do: via(naming, {:kernel_core, kernel_name(naming)})

  @spec via_kernel_registry(t()) :: {:via, Registry, {atom(), tuple()}}
  def via_kernel_registry(%__MODULE__{} = naming),
    do: via(naming, {:kernel_registry, kernel_name(naming)})

  @spec via_kernel_task_supervisor(t()) :: {:via, Registry, {atom(), tuple()}}
  def via_kernel_task_supervisor(%__MODULE__{} = naming),
    do: via(naming, {:kernel_task_supervisor, kernel_name(naming)})

  @spec kernel_pod_manager(t()) :: atom()
  def kernel_pod_manager(%__MODULE__{} = naming) do
    manager_atom(["kernel", kernel_name(naming), "pods"])
  end

  @spec kernel_jido_instance(t()) :: atom()
  def kernel_jido_instance(%__MODULE__{} = naming) do
    manager_atom(["kernel", kernel_name(naming), "jido"])
  end

  @spec runtime_pod_key(t(), term()) :: {:agent_os_kernel_pod, kernel_name(), String.t()}
  def runtime_pod_key(%__MODULE__{} = naming, pod_id) do
    {:agent_os_kernel_pod, kernel_name(naming), pod_id(pod_id)}
  end

  @spec user_pod_id(term()) :: String.t()
  def user_pod_id({:agent_os_kernel_pod, _kernel_name, pod_id}), do: pod_id
  def user_pod_id(value), do: pod_id(value)

  @spec manager_atom([term()]) :: atom()
  def manager_atom(parts) when is_list(parts) do
    suffix =
      parts
      |> Enum.map(&normalize_manager_part/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("__")

    String.to_atom("jido_agent_os__" <> suffix)
  end

  defp via(%__MODULE__{} = naming, key),
    do: {:via, Registry, {Jido.AgentOS.ProcessRegistry, {kernel_name(naming), key}}}

  defp normalize_kernel(nil), do: @default_kernel
  defp normalize_kernel(value) when is_atom(value), do: value

  defp normalize_kernel(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @default_kernel
      normalized -> normalized
    end
  end

  defp normalize_kernel(value) do
    value
    |> to_string()
    |> normalize_kernel()
  end

  defp normalize_manager_part(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_manager_part()
  end

  defp normalize_manager_part(value) when is_binary(value) do
    value
    |> String.replace(~r/[^a-zA-Z0-9]+/u, "_")
    |> String.trim("_")
    |> String.downcase()
  end

  defp normalize_manager_part(value) do
    value
    |> to_string()
    |> normalize_manager_part()
  end
end
