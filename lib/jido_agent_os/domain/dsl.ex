defmodule Jido.Domain.Dsl do
  @moduledoc false

  alias Spark.Builder.{Entity, Field, Section}

  defmodule DomainConfig do
    @moduledoc false
    defstruct [:name, :kernel, :pod, :description, :__spark_metadata__]
  end

  defmodule Action do
    @moduledoc false
    defstruct [:name, :args, :delegate_to, :as, :doc, :kind, :__identifier__, :__spark_metadata__]
  end

  @domain Section.new(:domain,
            describe: "Configure the domain boundary above a pod-backed runtime.",
            schema: [
              Field.new(:name, :atom, required: true, doc: "The stable domain name."),
              Field.new(:kernel, :atom,
                required: true,
                doc: "The kernel wrapper module that runs the runtime."
              ),
              Field.new(:pod, :atom,
                required: true,
                doc: "The pod module wrapped by this domain."
              ),
              Field.new(:description, :string, doc: "Optional domain documentation.")
            ]
          )
          |> Section.build!()

  @action_schema [
    Field.new(:name, :atom, required: true, doc: "The public function name."),
    Field.new(:args, {:list, :atom},
      doc: "The generated function arguments in order.",
      default: []
    ),
    Field.new(:delegate_to, :atom,
      required: true,
      doc: "The implementation module called by the generated function."
    ),
    Field.new(:as, :atom, doc: "Optional implementation function name override."),
    Field.new(:doc, :string, doc: "Optional generated documentation.")
  ]

  @command Entity.new(:command, Action,
             args: [:name],
             auto_set_fields: [kind: :command],
             describe: "Defines a generated public command function.",
             identifier: :name,
             schema: @action_schema
           )
           |> Entity.build!()

  @query Entity.new(:query, Action,
           args: [:name],
           auto_set_fields: [kind: :query],
           describe: "Defines a generated public query function.",
           identifier: :name,
           schema: @action_schema
         )
         |> Entity.build!()

  @commands Section.new(:commands,
              describe: "Declare the public command API for the domain.",
              entities: [@command]
            )
            |> Section.build!()

  @queries Section.new(:queries,
             describe: "Declare the public query API for the domain.",
             entities: [@query]
           )
           |> Section.build!()

  use Spark.Dsl.Extension,
    sections: [@domain, @commands, @queries],
    transformers: [Jido.Domain.Transformers.GenerateApi],
    module_prefix: Jido.Domain.Dsl.Generated
end
