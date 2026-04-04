defmodule JidoOSDevAgents.Actions.Tools.CurrentTask do
  @moduledoc false

  use Jido.Action,
    name: "repo_current_task",
    description: "Return the currently selected coding task.",
    schema: []

  @impl true
  def run(_params, context) do
    case context[:task] || get_in(context, [:tool_context, :task]) ||
           get_in(context, [:tool_context, "task"]) do
      nil -> {:error, :missing_task_context}
      task -> {:ok, %{task: task}}
    end
  end
end
