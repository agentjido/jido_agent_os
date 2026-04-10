defmodule Jido.DomainTest do
  use ExUnit.Case, async: true

  doctest Jido.Domain

  defmodule ExampleAgent do
    use Jido.Agent,
      name: "domain_test_agent"
  end

  defmodule ExamplePod do
    use Jido.AgentOS.Pod,
      name: "domain_test_pod",
      topology: %{
        controller: %{agent: ExampleAgent, manager: :controller, activation: :eager}
      }
  end

  defmodule ExampleKernel do
    use Jido.AgentOS,
      name: :domain_test_kernel,
      pod: ExamplePod
  end

  defmodule ExampleImpl do
    def status, do: %{status: :ok}
    def submit_task(pod_id, task), do: {:ok, %{pod_id: pod_id, task: task}}
    def fetch_timeline(pod_id), do: {:ok, ["timeline:" <> pod_id]}
  end

  defmodule ExampleDomain do
    use Jido.Domain

    domain do
      name(:example_workspace)
      kernel(ExampleKernel)
      pod(ExamplePod)
    end

    commands do
      command(:submit_task,
        args: [:pod_id, :task],
        delegate_to: ExampleImpl,
        doc: "Submits work to the example domain."
      )
    end

    queries do
      query(:status, delegate_to: ExampleImpl)

      query(:timeline,
        args: [:pod_id],
        delegate_to: ExampleImpl,
        as: :fetch_timeline
      )
    end
  end

  test "marks modules as domains and exposes domain metadata" do
    assert Jido.Domain.domain?(ExampleDomain)
    refute Jido.Domain.domain?(ExampleImpl)

    assert ExampleDomain.domain_name() == :example_workspace
    assert ExampleDomain.domain_kernel() == ExampleKernel
    assert ExampleDomain.domain_pod() == ExamplePod

    assert ExampleDomain.domain_config() == %{
             name: :example_workspace,
             kernel: ExampleKernel,
             pod: ExamplePod
           }
  end

  test "exposes configured command and query metadata" do
    assert [%{name: :submit_task, kind: :command}] = ExampleDomain.commands()

    assert Enum.map(ExampleDomain.queries(), &{&1.name, &1.kind}) == [
             {:status, :query},
             {:timeline, :query}
           ]

    assert ExampleDomain.command(:submit_task).delegate_to == ExampleImpl
    assert ExampleDomain.query(:timeline).as == :fetch_timeline
  end

  test "generates command and query wrapper functions" do
    assert ExampleDomain.status() == %{status: :ok}

    assert ExampleDomain.submit_task("pod-1", %{title: "Test"}) ==
             {:ok, %{pod_id: "pod-1", task: %{title: "Test"}}}

    assert ExampleDomain.timeline("pod-1") == {:ok, ["timeline:pod-1"]}
  end

  test "dispatches commands and queries through metadata" do
    assert ExampleDomain.dispatch_command(:submit_task, ["pod-2", %{title: "Queued"}]) ==
             {:ok, %{pod_id: "pod-2", task: %{title: "Queued"}}}

    assert ExampleDomain.dispatch_query(:timeline, ["pod-2"]) == {:ok, ["timeline:pod-2"]}
  end
end
