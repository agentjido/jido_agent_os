defmodule Jido.Domain do
  @moduledoc """
  Spark-backed authoring layer for host-facing domain APIs above AgentOS pods.

  `Jido.Domain` is not a runtime primitive. It defines a stable integration
  boundary between a host application and a pod-backed runtime by generating a
  public command/query API from DSL metadata.
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [Jido.Domain.Dsl]
    ]

  alias Jido.Domain.Info

  @type action_kind :: :command | :query
  @type action_name :: atom()

  @doc """
  Returns true when the module exposes the generated domain marker.
  """
  @spec domain?(module()) :: boolean()
  def domain?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__jido_domain__, 0) and
      module.__jido_domain__()
  end

  @doc """
  Returns the generated domain configuration.
  """
  @spec domain_config(module()) :: map()
  def domain_config(module) when is_atom(module) do
    %{
      name: Info.domain_name!(module),
      kernel: Info.domain_kernel!(module),
      pod: Info.domain_pod!(module)
    }
  end

  @doc """
  Returns all configured command entities for the given domain.
  """
  @spec commands(module()) :: list(struct())
  def commands(module) when is_atom(module), do: Info.commands(module)

  @doc """
  Returns all configured query entities for the given domain.
  """
  @spec queries(module()) :: list(struct())
  def queries(module) when is_atom(module), do: Info.queries(module)

  @doc """
  Returns the configured command by name, or `nil` when absent.
  """
  @spec command(module(), action_name()) :: struct() | nil
  def command(module, name) when is_atom(module) and is_atom(name) do
    Enum.find(commands(module), &(&1.name == name))
  end

  @doc """
  Returns the configured query by name, or `nil` when absent.
  """
  @spec query(module(), action_name()) :: struct() | nil
  def query(module, name) when is_atom(module) and is_atom(name) do
    Enum.find(queries(module), &(&1.name == name))
  end

  @doc """
  Dispatches a generated command/query call to its implementation module.
  """
  @spec dispatch(module(), action_kind(), action_name(), [term()]) :: term()
  def dispatch(module, kind, name, args \\ [])

  def dispatch(module, kind, name, args)
      when is_atom(module) and kind in [:command, :query] and is_atom(name) and is_list(args) do
    action = fetch_action!(module, kind, name)
    delegate = action.as || action.name

    apply(action.delegate_to, delegate, args)
  end

  defp fetch_action!(module, :command, name) do
    command(module, name) ||
      raise ArgumentError,
            "unknown Jido.Domain command #{inspect(name)} for #{inspect(module)}"
  end

  defp fetch_action!(module, :query, name) do
    query(module, name) ||
      raise ArgumentError,
            "unknown Jido.Domain query #{inspect(name)} for #{inspect(module)}"
  end
end
