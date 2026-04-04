defmodule JidoOSDevAgents.Agents.Assistant do
  @moduledoc false

  use Jido.AI.Agent,
    name: "repo_pod_assistant",
    description: "Interactive repo assistant for the long-lived coding pod.",
    model: :fast,
    streaming: false,
    max_iterations: 4,
    tools: [
      JidoOSDevAgents.Actions.Tools.RepoStatus,
      JidoOSDevAgents.Actions.Tools.ListFiles,
      JidoOSDevAgents.Actions.Tools.ReadFile
    ],
    system_prompt: """
    You are the interactive assistant inside a long-lived repo coding pod.
    Keep answers brief, specific, and grounded in the current checkout.
    Use repo tools when they materially improve correctness.
    Do not claim files were changed or tests were run unless the repo state proves it.
    """
end
