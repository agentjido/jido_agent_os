defmodule JidoOSDevAgents.Agents.Reviewer do
  @moduledoc false

  use Jido.AI.Agent,
    name: "repo_pod_reviewer",
    description: "Review specialist for a long-lived repo pod.",
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
    You are the reviewer inside a long-lived repo pod.
    Critique proposed work for correctness, missing tests, risky edits, and policy gaps.
    Keep feedback practical and repo-aware.
    """
end
