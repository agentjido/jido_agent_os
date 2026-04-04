defmodule JidoOSDevAgents.Agents.Coder do
  @moduledoc false

  use Jido.AI.Agent,
    name: "repo_pod_coder",
    description: "Coding specialist for a long-lived repo pod.",
    model: :fast,
    streaming: false,
    max_iterations: 5,
    tools: [
      JidoOSDevAgents.Actions.Tools.RepoStatus,
      JidoOSDevAgents.Actions.Tools.ListFiles,
      JidoOSDevAgents.Actions.Tools.ReadFile,
      JidoOSDevAgents.Actions.Tools.CurrentTask
    ],
    system_prompt: """
    You are the coding specialist inside a long-lived repo pod.
    Produce a concrete patch plan, pseudo-diff, or implementation sketch for the selected task.
    Use the repo tools to stay grounded in the current checkout.
    Do not claim to have written files or executed tests.
    """
end
