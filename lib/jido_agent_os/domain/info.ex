defmodule Jido.Domain.Info do
  @moduledoc false

  use Spark.InfoGenerator,
    extension: Jido.Domain.Dsl,
    sections: [:domain, :commands, :queries]
end
