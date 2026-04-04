defmodule Jido.AgentOSPodTest do
  use ExUnit.Case, async: true

  defmodule ExampleAgent do
    use Jido.Agent,
      name: "agent_os_pod_test_agent"
  end

  defmodule AuditPlugin do
    use Jido.Plugin,
      name: "audit",
      state_key: :audit,
      actions: [],
      schema:
        Zoi.object(%{
          enabled: Zoi.boolean() |> Zoi.default(true)
        }),
      singleton: true
  end

  defmodule ExamplePod do
    use Jido.AgentOS.Pod,
      name: "plugin_passthrough_pod",
      plugins: [{AuditPlugin, %{enabled: false}}],
      topology: %{
        controller: %{agent: ExampleAgent, manager: :controller, activation: :eager}
      }
  end

  test "passes through standard Jido plugin configuration" do
    assert Jido.Pod.Plugin in ExamplePod.plugins()
    assert AuditPlugin in ExamplePod.plugins()
    assert ExamplePod.plugin_config(AuditPlugin) == %{enabled: false}
  end
end
