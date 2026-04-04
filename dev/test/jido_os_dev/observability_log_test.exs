defmodule JidoOSDev.ObservabilityLogTest do
  use ExUnit.Case, async: false

  test "captures telemetry events and exposes filtered entries" do
    seq = JidoOSDev.ObservabilityLog.current_seq()

    :telemetry.execute(
      [:jido, :ai, :tool, :complete],
      %{duration_ms: 17},
      %{
        agent_id: "assistant-node",
        jido_partition: "pod-test",
        request_id: "req-123",
        tool_name: "read_file"
      }
    )

    entries =
      JidoOSDev.ObservabilityLog.entries_since(seq,
        pod_id: "pod-test",
        agent_id: "assistant-node",
        family: :ai_tool
      )

    assert [%{tool_name: "read_file", family: :ai_tool, duration_ms: 17} = entry] = entries
    assert entry.event == "jido.ai.tool.complete"
    assert entry.summary =~ "read_file complete"
  end
end
