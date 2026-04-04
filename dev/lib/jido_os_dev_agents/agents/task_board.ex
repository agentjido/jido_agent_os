defmodule JidoOSDevAgents.Agents.TaskBoard do
  @moduledoc false

  use Jido.Agent,
    name: "repo_pod_task_board",
    signal_routes: [
      {"task.add", JidoOSDevAgents.Actions.TaskBoard.AddTask},
      {"task.select", JidoOSDevAgents.Actions.TaskBoard.SelectTask},
      {"task.store", JidoOSDevAgents.Actions.TaskBoard.StoreArtifact},
      {"task.event", JidoOSDevAgents.Actions.TaskBoard.AppendEvent}
    ],
    schema: [
      tasks: [type: {:list, :any}, default: []],
      active_task_id: [type: :string, default: ""],
      activity_log: [type: {:list, :any}, default: []]
    ]
end
