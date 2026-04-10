defmodule JidoOSDev.RepoWorkspace do
  @moduledoc """
  Phoenix context for the sample repo workspace.

  This is the public API the Phoenix host calls. It sits above the durable
  AgentOS runtime and translates domain-shaped workspace operations into lower-
  level pod, node, and signal interactions.

  The intended layout is:

  - `JidoOSDev.RepoWorkspace`: public Phoenix context
  - `JidoOSDev.RepoWorkspace.*`: private context internals
  - `JidoOSDevAgents.*`: sibling runtime subsystem

  That split keeps the host app Phoenix-native. Controllers and LiveViews call
  the context, while the context reaches into `JidoOSDevAgents` on their
  behalf. End developers should not need to coordinate nodes, prompts, or
  signals from transport code.
  """

  use Jido.Domain

  alias __MODULE__.{Config, Runtime, Workflow}
  alias JidoOSDevAgents.Pods.RepoPod

  domain do
    name(:repo_workspace)
    kernel(JidoOSDevAgents)
    pod(RepoPod)
  end

  queries do
    query(:kernel_status, delegate_to: Config)
    query(:configured_pod, delegate_to: Config)
    query(:ai_ready?, delegate_to: Config)
    query(:list_pods, delegate_to: Config)
    query(:default_repo_path, delegate_to: Config)
    query(:default_pod_id, delegate_to: Config)
    query(:pod_overview, args: [:pod_id], delegate_to: Runtime)
  end

  commands do
    command(:ensure_pod, args: [:pod_id, :repo_path], delegate_to: Runtime)
    command(:sync_repo, args: [:pod_id, :repo_path], delegate_to: Runtime)
    command(:add_task, args: [:pod_id, :title, :goal], delegate_to: Runtime)
    command(:select_task, args: [:pod_id, :task_id], delegate_to: Runtime)
    command(:plan_task, args: [:pod_id, :task_id], delegate_to: Workflow)
    command(:draft_task, args: [:pod_id, :task_id], delegate_to: Workflow)
    command(:review_task, args: [:pod_id, :task_id], delegate_to: Workflow)
    command(:chat_with_pod, args: [:pod_id, :prompt], delegate_to: Workflow)
    command(:run_workflow, args: [:pod_id, :task_id], delegate_to: Workflow)
    command(:reconcile_pod, args: [:pod_id], delegate_to: Runtime)
    command(:wake_specialist, args: [:pod_id, :specialist], delegate_to: Runtime)
  end

  @doc "Ensures a repo workspace pod using the configured default repo path."
  @spec ensure_pod(String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(pod_id), do: ensure_pod(pod_id, Config.default_repo_path())

  @doc "Syncs a repo workspace using the configured default repo path."
  @spec sync_repo(String.t()) :: {:ok, map()} | {:error, term()}
  def sync_repo(pod_id), do: sync_repo(pod_id, Config.default_repo_path())
end
