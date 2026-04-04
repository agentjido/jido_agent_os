defmodule JidoOSDevAgents.Pods.RepoPodTest do
  use ExUnit.Case, async: true

  alias JidoOSDevAgents.Pods.RepoPod

  test "defines the canonical repo coding pod for one repo checkout" do
    {:ok, topology} = Jido.Pod.fetch_topology(RepoPod)

    assert topology.name == "repo_pod"
    assert map_size(topology.nodes) == 6
    assert Map.has_key?(topology.nodes, :repo_state)
    assert Map.has_key?(topology.nodes, :task_board)
    assert Map.has_key?(topology.nodes, :assistant)
    assert Map.has_key?(topology.nodes, :planner)
    assert Map.has_key?(topology.nodes, :coder)
    assert Map.has_key?(topology.nodes, :reviewer)

    summary = Jido.AgentOS.Pod.summary(RepoPod)

    assert summary.name == "repo_pod"
    assert summary.module == "JidoOSDevAgents.Pods.RepoPod"
    assert length(summary.nodes) == 6
    assert "repo_state" in summary.nodes
    assert "task_board" in summary.nodes
    assert "assistant" in summary.nodes
    assert "planner" in summary.nodes
    assert "coder" in summary.nodes
    assert "reviewer" in summary.nodes
  end
end
