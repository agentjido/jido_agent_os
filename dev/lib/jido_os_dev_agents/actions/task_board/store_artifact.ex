defmodule JidoOSDevAgents.Actions.TaskBoard.StoreArtifact do
  @moduledoc false

  use Jido.Action,
    name: "task_board_store_artifact",
    description: "Persist a specialist output on a coding task.",
    schema: [
      task_id: [type: :string, required: true],
      stage: [type: :string, required: true],
      content: [type: :string, required: true],
      status: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(%{task_id: task_id, stage: stage, content: content, status: status}, context) do
    tasks = Map.get(context.state, :tasks, [])
    activity_log = Map.get(context.state, :activity_log, [])

    with {:ok, stage_key} <- stage_key(stage),
         {:ok, updated_tasks, updated_task} <-
           update_task(tasks, task_id, stage_key, content, status) do
      event = %{
        at: now(),
        kind: "task_#{stage}",
        message: "#{String.capitalize(stage)} completed for #{updated_task.title}.",
        task_id: task_id
      }

      {:ok, updated_task,
       StateOp.set_state(%{
         tasks: updated_tasks,
         active_task_id: task_id,
         activity_log: [event | activity_log] |> Enum.take(24)
       })}
    end
  end

  defp update_task(tasks, task_id, stage_key, content, status) do
    if Enum.any?(tasks, &(&1.id == task_id)) do
      updated =
        Enum.map(tasks, fn task ->
          if task.id == task_id do
            task
            |> Map.put(stage_key, content)
            |> Map.put(:status, status)
            |> Map.put(:updated_at, now())
          else
            task
          end
        end)

      {:ok, updated, Enum.find(updated, &(&1.id == task_id))}
    else
      {:error, :task_not_found}
    end
  end

  defp stage_key("plan"), do: {:ok, :plan}
  defp stage_key("draft"), do: {:ok, :draft}
  defp stage_key("review"), do: {:ok, :review}
  defp stage_key(_other), do: {:error, :invalid_stage}

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
