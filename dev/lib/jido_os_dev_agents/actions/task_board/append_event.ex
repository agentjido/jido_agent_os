defmodule JidoOSDevAgents.Actions.TaskBoard.AppendEvent do
  @moduledoc false

  use Jido.Action,
    name: "task_board_append_event",
    description: "Append an activity event to the repo pod task board.",
    schema: [
      kind: [type: :string, required: true],
      message: [type: :string, required: true],
      task_id: [type: :string, required: false]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(params, context) do
    event = %{
      at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      kind: params.kind,
      message: params.message,
      task_id: Map.get(params, :task_id)
    }

    {:ok, event,
     StateOp.set_state(%{
       activity_log: [event | Map.get(context.state, :activity_log, [])] |> Enum.take(24)
     })}
  end
end
