defmodule Jido.AgentOSTest do
  use ExUnit.Case
  doctest Jido.AgentOS

  alias Jido.Agent.InstanceManager
  alias Jido.AgentOS.Pod, as: AgentOSPod

  defmodule ExampleAgent do
    use Jido.Agent,
      name: "agent_os_test_agent",
      schema: [
        role: [type: :string, default: "test"]
      ]
  end

  defmodule ExamplePod do
    use Jido.AgentOS.Pod,
      name: "kernel_pod",
      topology: %{
        controller: %{agent: ExampleAgent, manager: :kernel_agents, activation: :eager},
        worker: %{agent: ExampleAgent, manager: :kernel_agents, activation: :lazy}
      }
  end

  test "exposes the root supervisor module" do
    assert Jido.AgentOS.root_supervisor() == Jido.AgentOS.Supervisor
  end

  test "starts isolated kernel supervisors with separate names" do
    kernel_a = start_kernel!(:os_alpha)
    kernel_b = start_kernel!(:os_beta)

    assert Process.alive?(kernel_a)
    assert Process.alive?(kernel_b)
    assert kernel_a != kernel_b
  end

  test "keeps pods isolated across kernels even with the same id" do
    start_kernel!(:os_left)
    start_kernel!(:os_right)
    wait_for_managers_started(:os_left)
    wait_for_managers_started(:os_right)

    assert {:ok, left_pid} = Jido.AgentOS.ensure_pod(:os_left, "shared")
    assert {:ok, right_pid} = Jido.AgentOS.ensure_pod(:os_right, "shared")
    assert left_pid != right_pid

    assert {:ok, ^left_pid} = Jido.AgentOS.pod_pid(:os_left, "shared")
    assert {:ok, ^right_pid} = Jido.AgentOS.pod_pid(:os_right, "shared")

    assert Jido.AgentOS.list_pods(:os_left) == ["shared"]
    assert Jido.AgentOS.list_pods(:os_right) == ["shared"]
  end

  test "returns per-pod snapshots" do
    start_kernel!(:os_snapshot)
    wait_for_managers_started(:os_snapshot)

    assert {:ok, _pid} = Jido.AgentOS.ensure_pod(:os_snapshot, :primary)

    assert {:ok, snapshot} = Jido.AgentOS.pod_snapshot(:os_snapshot, :primary)
    assert snapshot.kernel_name == :os_snapshot
    assert snapshot.pod_id == "primary"
    assert snapshot.topology_name == "kernel_pod"
    assert snapshot.nodes == ["controller", "worker"]
    assert is_pid(snapshot.pid)
  end

  test "threads pod metadata through kernel status and pod snapshots" do
    start_kernel!(:os_kernel)
    wait_for_managers_started(:os_kernel)

    assert {:ok, _pid} = Jido.AgentOS.ensure_pod(:os_kernel, :primary)
    assert {:ok, snapshot} = Jido.AgentOS.pod_snapshot(:os_kernel, :primary)

    assert snapshot.pod.name == "kernel_pod"
    assert snapshot.pod.nodes == ["controller", "worker"]

    status = Jido.AgentOS.kernel_status(:os_kernel)

    assert status.pod.name == "kernel_pod"
    assert status.pod.nodes == ["controller", "worker"]
    assert status.pods == ["primary"]
  end

  defp start_kernel!(name) do
    start_supervised!({Jido.AgentOS, name: name, pod: ExamplePod})
  end

  defp wait_for_managers_started(kernel_name) do
    Enum.each(AgentOSPod.runtime_manager_specs(ExamplePod, kernel_name), fn spec ->
      try do
        Enum.each(1..20, fn _attempt ->
          case InstanceManager.agent_module(spec.name) do
            {:ok, ExampleAgent} ->
              throw(:done)

            _other ->
              Process.sleep(5)
          end
        end)
      catch
        :done -> :ok
      end
    end)
  end
end
