defmodule JidoOSDevAgents.Actions.TaskBoard.SelectTask do
  @moduledoc false

  use Jido.Action,
    name: "task_board_select_task",
    description: "Select the active coding task.",
    schema: [
      task_id: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(%{task_id: task_id}, context) do
    tasks = Map.get(context.state, :tasks, [])

    if Enum.any?(tasks, &(&1.id == task_id)) do
      {:ok, %{active_task_id: task_id}, StateOp.set_state(%{active_task_id: task_id})}
    else
      {:error, :task_not_found}
    end
  end
end
