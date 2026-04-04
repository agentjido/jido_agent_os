defmodule Jido.AgentOSPersistenceTest do
  use ExUnit.Case

  alias Jido.AgentOS.Persistence

  defmodule ExampleStorage do
  end

  defmodule ExampleRepo do
  end

  test "normalizes adapter keyword config into a storage tuple" do
    persistence =
      Jido.AgentOS.kernel_persistence(
        persistence: [adapter: ExampleStorage, repo: ExampleRepo, prefix: "agent_os"]
      )

    assert %Persistence{} = persistence
    assert persistence.adapter == ExampleStorage
    assert persistence.options[:repo] == ExampleRepo
    assert persistence.options[:prefix] == "agent_os"

    assert Jido.AgentOS.kernel_storage(
             persistence: [adapter: ExampleStorage, repo: ExampleRepo, prefix: "agent_os"]
           ) == {ExampleStorage, [repo: ExampleRepo, prefix: "agent_os"]}
  end

  test "summarizes persistence for kernel status" do
    persistence =
      Jido.AgentOS.kernel_persistence(
        persistence: [adapter: ExampleStorage, repo: ExampleRepo, prefix: "agent_os"]
      )

    assert Persistence.summary(persistence) == %{
             adapter: "Jido.AgentOSPersistenceTest.ExampleStorage",
             repo: "Jido.AgentOSPersistenceTest.ExampleRepo",
             options: %{"prefix" => "agent_os"}
           }
  end
end
