defmodule Jido.Domain.Transformers.GenerateApi do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Jido.Domain.Info

  @impl true
  def transform(dsl_state) do
    domain_name = Info.domain_name!(dsl_state)
    kernel = Info.domain_kernel!(dsl_state)
    pod = Info.domain_pod!(dsl_state)
    commands = Info.commands(dsl_state)
    queries = Info.queries(dsl_state)

    generated =
      quote do
        @doc false
        def __jido_domain__, do: true

        @doc "Returns the configured domain metadata."
        def domain_config do
          Jido.Domain.domain_config(__MODULE__)
        end

        @doc "Returns the configured domain name."
        def domain_name, do: unquote(domain_name)

        @doc "Returns the configured kernel wrapper."
        def domain_kernel, do: unquote(kernel)

        @doc "Returns the configured pod module."
        def domain_pod, do: unquote(pod)

        @doc "Returns configured command metadata."
        def commands, do: Jido.Domain.commands(__MODULE__)

        @doc "Returns configured query metadata."
        def queries, do: Jido.Domain.queries(__MODULE__)

        @doc "Returns a configured command by name."
        def command(name), do: Jido.Domain.command(__MODULE__, name)

        @doc "Returns a configured query by name."
        def query(name), do: Jido.Domain.query(__MODULE__, name)

        @doc "Dispatches a configured command by name."
        def dispatch_command(name, args \\ []),
          do: Jido.Domain.dispatch(__MODULE__, :command, name, args)

        @doc "Dispatches a configured query by name."
        def dispatch_query(name, args \\ []),
          do: Jido.Domain.dispatch(__MODULE__, :query, name, args)

        unquote_splicing(Enum.map(commands, &action_ast(&1, :command)))
        unquote_splicing(Enum.map(queries, &action_ast(&1, :query)))
      end

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], generated)}
  end

  defp action_ast(action, kind) do
    args = Enum.map(action.args || [], &Macro.var(&1, nil))
    doc = action.doc || "Dispatches the domain #{kind} `#{action.name}`."

    quote do
      @doc unquote(doc)
      def unquote(action.name)(unquote_splicing(args)) do
        Jido.Domain.dispatch(__MODULE__, unquote(kind), unquote(action.name), [
          unquote_splicing(args)
        ])
      end
    end
  end
end
