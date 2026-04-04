defmodule JidoOSDev.RepoWorkspace.Workflow do
  @moduledoc false

  alias Jido.AgentServer
  alias JidoOSDevAgents.Agents.{Assistant, Coder, Planner, Reviewer}
  alias JidoOSDev.ObservabilityLog
  alias JidoOSDev.RepoWorkspace.{Config, Prompts, Runtime, Summary}

  @specialists %{assistant: Assistant, planner: Planner, coder: Coder, reviewer: Reviewer}

  @spec plan_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def plan_task(pod_id, task_id), do: run_specialist(pod_id, :planner, task_id)

  @spec draft_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def draft_task(pod_id, task_id), do: run_specialist(pod_id, :coder, task_id)

  @spec review_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def review_task(pod_id, task_id), do: run_specialist(pod_id, :reviewer, task_id)

  @spec chat_with_pod(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def chat_with_pod(pod_id, prompt) do
    prompt = prompt |> to_string() |> String.trim()

    cond do
      prompt == "" ->
        {:error, :empty_prompt}

      not Config.ai_ready?() ->
        {:error, :ai_not_configured}

      true ->
        with {:ok, repo} <- Runtime.fetch_repo_state(pod_id),
             {:ok, task_board} <- Runtime.fetch_task_board(pod_id),
             active_task = Summary.active_task(task_board),
             {:ok, pid} <- Runtime.wake_specialist(pod_id, :assistant),
             {:ok, server_state} <- AgentServer.state(pid),
             cursor <- ObservabilityLog.current_seq(),
             {:ok, answer} <-
               Assistant.ask_sync(
                 pid,
                 Prompts.assistant_prompt(repo, active_task, prompt),
                 tool_context: %{
                   repo_path: repo.repo_path,
                   repo: repo,
                   task: active_task,
                   prompt: prompt
                 },
                 timeout: 60_000
               ) do
          task_id =
            case active_task do
              nil -> nil
              task -> task.id
            end

          _ =
            Runtime.append_event(
              pod_id,
              "assistant_reply",
              "Assistant answered a repo question.",
              task_id
            )

          ObservabilityLog.record(%{
            pod_id: pod_id,
            family: :ai_request,
            stage: "complete",
            event: "assistant.chat",
            agent_id: "assistant",
            summary: "Assistant answered a repo question.",
            details: %{task_id: task_id}
          })

          tool_events =
            Runtime.assistant_tool_events(cursor, stringify(server_state.id), pod_id)
            |> Enum.map(&Summary.summarize_tool_event/1)

          {:ok, %{answer: answer, tool_events: tool_events}}
        end
    end
  end

  @spec run_workflow(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def run_workflow(pod_id, task_id) do
    with {:ok, plan} <- plan_task(pod_id, task_id),
         {:ok, draft} <- draft_task(pod_id, task_id),
         {:ok, review} <- review_task(pod_id, task_id) do
      {:ok, %{plan: plan, draft: draft, review: review}}
    end
  end

  defp run_specialist(pod_id, specialist, task_id) do
    if Config.ai_ready?() do
      with {:ok, repo} <- Runtime.fetch_repo_state(pod_id),
           {:ok, task_board} <- Runtime.fetch_task_board(pod_id),
           {:ok, task} <- Runtime.fetch_task(task_board, task_id),
           {:ok, pid} <- Runtime.wake_specialist(pod_id, specialist),
           {:ok, output} <-
             specialist_module(specialist).ask_sync(
               pid,
               Prompts.specialist_prompt(specialist, repo, task),
               tool_context: %{repo_path: repo.repo_path, repo: repo, task: task},
               timeout: 60_000
             ),
           {:ok, _task_board} <-
             Runtime.store_artifact(pod_id, task_id, specialist_stage(specialist), output) do
        ObservabilityLog.record(%{
          pod_id: pod_id,
          family: :ai_request,
          stage: "complete",
          event: "specialist.#{specialist}",
          agent_id: Atom.to_string(specialist),
          summary:
            "#{String.capitalize(Atom.to_string(specialist))} completed for #{task.title}.",
          details: %{task_id: task_id}
        })

        {:ok, output}
      end
    else
      {:error, :ai_not_configured}
    end
  end

  defp specialist_stage(:planner), do: {"plan", "planned"}
  defp specialist_stage(:coder), do: {"draft", "drafted"}
  defp specialist_stage(:reviewer), do: {"review", "reviewed"}

  defp specialist_module(key), do: Map.fetch!(@specialists, key)

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: inspect(value)
end
