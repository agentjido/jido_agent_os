defmodule JidoOSDevAgents.Actions.TaskBoard.AddTask do
  @moduledoc false

  use Jido.Action,
    name: "task_board_add_task",
    description: "Queue a coding task for the repo pod.",
    schema: [
      title: [type: :string, required: true],
      goal: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(%{title: title, goal: goal}, context) do
    title = String.trim(title)
    goal = String.trim(goal)

    cond do
      title == "" -> {:error, :empty_title}
      goal == "" -> {:error, :empty_goal}
      true -> persist_task(title, goal, context)
    end
  end

  defp persist_task(title, goal, context) do
    now = now()
    tasks = Map.get(context.state, :tasks, [])
    activity_log = Map.get(context.state, :activity_log, [])

    active_task_id =
      context.state
      |> Map.get(:active_task_id)
      |> blank_to_nil()

    task = %{
      id: task_id(),
      title: title,
      goal: goal,
      status: "queued",
      plan: nil,
      draft: nil,
      review: nil,
      created_at: now,
      updated_at: now
    }

    event = %{
      at: now,
      kind: "task_added",
      message: "Queued task #{task.title}.",
      task_id: task.id
    }

    {:ok, task,
     StateOp.set_state(%{
       tasks: tasks ++ [task],
       active_task_id: active_task_id || task.id,
       activity_log: [event | activity_log] |> Enum.take(24)
     })}
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp task_id do
    System.unique_integer([:positive])
    |> Integer.to_string()
    |> then(&("task-" <> &1))
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
