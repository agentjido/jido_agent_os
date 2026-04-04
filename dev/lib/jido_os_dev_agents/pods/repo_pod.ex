defmodule JidoOSDevAgents.Pods.RepoPod do
  @moduledoc """
  Durable coding pod for one local Git checkout.

  The pod boundary represents one long-lived agent team watching a single repo:
  repo state, task board, planning, coding, and review.
  """

  use Jido.AgentOS.Pod,
    name: "repo_pod",
    topology: %{
      repo_state: %{
        agent: JidoOSDevAgents.Agents.RepoState,
        manager: :repo_state,
        activation: :eager
      },
      task_board: %{
        agent: JidoOSDevAgents.Agents.TaskBoard,
        manager: :task_board,
        activation: :eager
      },
      assistant: %{
        agent: JidoOSDevAgents.Agents.Assistant,
        manager: :assistant,
        activation: :lazy
      },
      planner: %{
        agent: JidoOSDevAgents.Agents.Planner,
        manager: :planning,
        activation: :lazy
      },
      coder: %{
        agent: JidoOSDevAgents.Agents.Coder,
        manager: :coding,
        activation: :lazy
      },
      reviewer: %{
        agent: JidoOSDevAgents.Agents.Reviewer,
        manager: :review,
        activation: :lazy
      }
    }
end
