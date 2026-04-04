defmodule JidoOSDev.RepoWorkspace.Runtime do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.Signal
  alias JidoOSDev.RepoWorkspace.{Config, Summary}

  @repo_state_node :repo_state
  @task_board_node :task_board
  @specialist_names [:assistant, :planner, :coder, :reviewer]

  @spec ensure_pod(String.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(pod_id, repo_path) do
    with {:ok, pid} <- JidoOSDevAgents.ensure_pod(pod_id),
         {:ok, _repo} <- sync_repo(pod_id, repo_path) do
      JidoOSDev.ObservabilityLog.record(%{
        pod_id: pod_id,
        family: :signal,
        stage: "complete",
        event: "pod.ensure",
        agent_id: "repo_workspace",
        signal_type: "pod.ensure",
        summary: "Ensured repo pod #{pod_id}.",
        details: %{repo_path: repo_path}
      })

      {:ok, pid}
    end
  end

  @spec pod_overview(String.t()) :: {:ok, map()} | {:error, term()}
  def pod_overview(pod_id) do
    with {:ok, pod} <- JidoOSDevAgents.pod_snapshot(pod_id) do
      {:ok,
       %{
         kernel: Config.kernel_status(),
         configured_pod: Config.configured_pod(),
         pod: pod,
         repo: repo_state_summary(pod_id),
         task_board: task_board_summary(pod_id),
         specialists: specialist_summaries(pod_id),
         ai_ready: Config.ai_ready?(),
         default_repo_path: Config.default_repo_path()
       }}
    end
  end

  @spec sync_repo(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def sync_repo(pod_id, repo_path) do
    with {:ok, repo_pid} <- JidoOSDevAgents.ensure_node(pod_id, @repo_state_node),
         {:ok, agent} <-
           AgentServer.call(
             repo_pid,
             Signal.new!(
               "repo.sync",
               %{repo_path: repo_path},
               source: "/jido_os_dev/repo_workspace"
             )
           ) do
      summary = Summary.summarize_repo_state(agent.state)

      _ =
        append_event(pod_id, "repo_synced", "Scanned #{summary.repo_name} on #{summary.branch}.")

      JidoOSDev.ObservabilityLog.record(%{
        pod_id: pod_id,
        family: :signal,
        stage: "complete",
        event: "repo.sync",
        agent_id: "repo_state",
        signal_type: "repo.sync",
        summary: "repo.sync complete on #{Summary.blank(summary.branch, "unknown")}.",
        details: %{repo: summary.repo_name, head: summary.head}
      })

      {:ok, summary}
    end
  end

  @spec add_task(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def add_task(pod_id, title, goal) do
    with {:ok, task_pid} <- JidoOSDevAgents.ensure_node(pod_id, @task_board_node),
         {:ok, agent} <-
           AgentServer.call(
             task_pid,
             Signal.new!(
               "task.add",
               %{title: title, goal: goal},
               source: "/jido_os_dev/repo_workspace"
             )
           ) do
      JidoOSDev.ObservabilityLog.record(%{
        pod_id: pod_id,
        family: :signal,
        stage: "complete",
        event: "task.add",
        agent_id: "task_board",
        signal_type: "task.add",
        summary: "Queued task #{title}.",
        details: %{title: title}
      })

      {:ok, Summary.summarize_task_board(agent.state)}
    end
  end

  @spec select_task(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def select_task(pod_id, task_id) do
    with {:ok, task_pid} <- JidoOSDevAgents.ensure_node(pod_id, @task_board_node),
         {:ok, agent} <-
           AgentServer.call(
             task_pid,
             Signal.new!(
               "task.select",
               %{task_id: task_id},
               source: "/jido_os_dev/repo_workspace"
             )
           ) do
      JidoOSDev.ObservabilityLog.record(%{
        pod_id: pod_id,
        family: :signal,
        stage: "complete",
        event: "task.select",
        agent_id: "task_board",
        signal_type: "task.select",
        summary: "Selected task #{task_id}.",
        details: %{task_id: task_id}
      })

      {:ok, Summary.summarize_task_board(agent.state)}
    end
  end

  @spec reconcile_pod(String.t()) :: {:ok, map()} | {:error, term()}
  def reconcile_pod(pod_id), do: JidoOSDevAgents.reconcile_pod(pod_id)

  @spec wake_specialist(String.t(), atom()) :: {:ok, pid()} | {:error, term()}
  def wake_specialist(pod_id, specialist) when is_atom(specialist) do
    if specialist in @specialist_names do
      JidoOSDevAgents.ensure_node(pod_id, specialist)
    else
      {:error, :unknown_specialist}
    end
  end

  @spec fetch_repo_state(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_repo_state(pod_id) do
    case running_node_state(pod_id, @repo_state_node) do
      {:ok, state} -> {:ok, Summary.summarize_repo_state(state)}
      error -> error
    end
  end

  @spec fetch_task_board(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_task_board(pod_id) do
    case running_node_state(pod_id, @task_board_node) do
      {:ok, state} -> {:ok, Summary.summarize_task_board(state)}
      error -> error
    end
  end

  @spec fetch_task(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_task(task_board, task_id) do
    case Enum.find(task_board.tasks, &(&1.id == task_id)) do
      nil -> {:error, :task_not_found}
      task -> {:ok, task}
    end
  end

  @spec store_artifact(String.t(), String.t(), {String.t(), String.t()}, String.t()) ::
          {:ok, map()} | {:error, term()}
  def store_artifact(pod_id, task_id, {stage, status}, content) do
    with {:ok, task_pid} <- JidoOSDevAgents.ensure_node(pod_id, @task_board_node),
         {:ok, agent} <-
           AgentServer.call(
             task_pid,
             Signal.new!(
               "task.store",
               %{task_id: task_id, stage: stage, content: content, status: status},
               source: "/jido_os_dev/repo_workspace"
             )
           ) do
      {:ok, Summary.summarize_task_board(agent.state)}
    end
  end

  @spec append_event(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, term()} | {:error, term()}
  def append_event(pod_id, kind, message, task_id \\ nil) do
    with {:ok, task_pid} <- JidoOSDevAgents.ensure_node(pod_id, @task_board_node) do
      params =
        %{kind: kind, message: message}
        |> maybe_put_task_id(task_id)

      AgentServer.call(
        task_pid,
        Signal.new!(
          "task.event",
          params,
          source: "/jido_os_dev/repo_workspace"
        )
      )
    end
  end

  @spec assistant_tool_events(non_neg_integer(), String.t() | nil, String.t()) :: [map()]
  def assistant_tool_events(cursor, agent_id, pod_id) do
    scoped =
      JidoOSDev.ObservabilityLog.entries_since(cursor,
        pod_id: pod_id,
        agent_id: agent_id,
        family: :ai_tool,
        limit: 12
      )

    if scoped == [] do
      JidoOSDev.ObservabilityLog.entries_since(cursor,
        agent_id: agent_id,
        family: :ai_tool,
        limit: 12
      )
    else
      scoped
    end
  end

  defp repo_state_summary(pod_id) do
    case fetch_repo_state(pod_id) do
      {:ok, repo} -> repo
      {:error, _reason} -> Summary.empty_repo_state(Config.default_repo_path())
    end
  end

  defp task_board_summary(pod_id) do
    case fetch_task_board(pod_id) do
      {:ok, task_board} -> task_board
      {:error, _reason} -> %{tasks: [], active_task_id: nil, activity_log: []}
    end
  end

  defp specialist_summaries(pod_id) do
    Enum.into(@specialist_names, %{}, fn name ->
      {name, specialist_summary(pod_id, name)}
    end)
  end

  defp specialist_summary(pod_id, name) do
    with {:ok, node_pid, state} <- running_node_server_state(pod_id, name) do
      Summary.summarize_specialist(name, node_pid, state)
    else
      _ -> Summary.empty_specialist(name)
    end
  end

  defp running_node_state(pod_id, node_name) do
    with {:ok, _node_pid, state} <- running_node_server_state(pod_id, node_name) do
      {:ok, state.agent.state}
    end
  end

  defp running_node_server_state(pod_id, node_name) do
    with {:ok, pod_pid} <- JidoOSDevAgents.pod_pid(pod_id),
         {:ok, node_pid} <- Jido.Pod.lookup_node(pod_pid, node_name),
         {:ok, state} <- AgentServer.state(node_pid) do
      {:ok, node_pid, state}
    else
      :error -> {:error, :node_not_running}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_task_id(params, nil), do: params
  defp maybe_put_task_id(params, ""), do: params
  defp maybe_put_task_id(params, task_id), do: Map.put(params, :task_id, task_id)
end
