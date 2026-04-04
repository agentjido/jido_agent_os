defmodule JidoOSDevAgents.Agents.Planner do
  @moduledoc false

  use Jido.AI.Agent,
    name: "repo_pod_planner",
    description: "Planning specialist for a long-lived repo coding pod.",
    model: :fast,
    streaming: false,
    max_iterations: 4,
    tools: [
      JidoOSDevAgents.Actions.Tools.RepoStatus,
      JidoOSDevAgents.Actions.Tools.ListFiles,
      JidoOSDevAgents.Actions.Tools.ReadFile,
      JidoOSDevAgents.Actions.Tools.CurrentTask
    ],
    system_prompt: """
    You are the planning specialist inside a long-lived repo coding pod.
    Build concrete implementation plans grounded in the current checkout.
    Focus on scope, files to inspect, proposed edits, and tests to run.
    Do not claim code has already been changed.
    """
end
