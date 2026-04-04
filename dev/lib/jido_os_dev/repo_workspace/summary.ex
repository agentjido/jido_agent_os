defmodule JidoOSDev.RepoWorkspace.Summary do
  @moduledoc false

  @spec summarize_repo_state(map()) :: map()
  def summarize_repo_state(state) do
    %{
      repo_path: blank_to_nil(Map.get(state, :repo_path)),
      repo_name: blank_to_nil(Map.get(state, :repo_name)),
      branch: blank_to_nil(Map.get(state, :branch)),
      head: blank_to_nil(Map.get(state, :head)),
      dirty: Map.get(state, :dirty, false),
      changed_files: Map.get(state, :changed_files, []),
      file_count: Map.get(state, :file_count, 0),
      changed_count: Map.get(state, :changed_count, 0),
      last_scan_at: blank_to_nil(Map.get(state, :last_scan_at))
    }
  end

  @spec summarize_task_board(map()) :: map()
  def summarize_task_board(state) do
    %{
      tasks: Map.get(state, :tasks, []),
      active_task_id: blank_to_nil(Map.get(state, :active_task_id)),
      activity_log: Map.get(state, :activity_log, [])
    }
  end

  @spec empty_repo_state(String.t()) :: map()
  def empty_repo_state(path) do
    %{
      repo_path: path,
      repo_name: Path.basename(path),
      branch: nil,
      head: nil,
      dirty: false,
      changed_files: [],
      file_count: 0,
      changed_count: 0,
      last_scan_at: nil
    }
  end

  @spec active_task(map()) :: map() | nil
  def active_task(%{tasks: tasks, active_task_id: task_id}) when is_list(tasks) do
    Enum.find(tasks, &(&1.id == task_id))
  end

  def active_task(_task_board), do: nil

  @spec active_task_summary(map() | nil) :: String.t()
  def active_task_summary(nil), do: "none selected"

  def active_task_summary(task) do
    "#{task.title}: #{task.goal}"
  end

  @spec summarize_tool_event(map()) :: map()
  def summarize_tool_event(entry) do
    %{
      tool_name: blank_to_nil(entry.tool_name) || "tool",
      stage: entry.stage,
      duration_ms: entry.duration_ms,
      summary: entry.summary
    }
  end

  @spec summarize_specialist(atom(), pid(), map()) :: map()
  def summarize_specialist(name, node_pid, state) do
    %{
      name: Atom.to_string(name),
      running: true,
      pid: inspect(node_pid),
      last_query: Map.get(state.agent.state, :last_query),
      last_answer: Map.get(state.agent.state, :last_answer),
      completed: Map.get(state.agent.state, :completed, false)
    }
  end

  @spec empty_specialist(atom()) :: map()
  def empty_specialist(name) do
    %{
      name: Atom.to_string(name),
      running: false,
      pid: nil,
      last_query: nil,
      last_answer: nil,
      completed: false
    }
  end

  @doc false
  def blank(value, fallback) when value in [nil, ""], do: fallback
  def blank(value, _fallback), do: value

  @doc false
  def blank_to_nil(value) when value in [nil, ""], do: nil
  def blank_to_nil(value), do: value
end
