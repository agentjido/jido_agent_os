defmodule JidoOSDev.RepoWorkspace do
  @moduledoc """
  Phoenix context for the sample repo workspace.

  This is the public API the Phoenix host calls. It sits above the durable
  AgentOS runtime and translates domain-shaped workspace operations into lower-
  level pod, node, and signal interactions.

  The intended layout is:

  - `JidoOSDev.RepoWorkspace`: public Phoenix context
  - `JidoOSDev.RepoWorkspace.*`: private context internals
  - `JidoOSDevAgents.*`: internal durable runtime topology

  That split keeps the host app Phoenix-native. Controllers and LiveViews call
  the context, while the context reaches into `Jido.AgentOS` on their behalf.
  End developers should not need to coordinate nodes, prompts, or signals from
  transport code.
  """

  alias __MODULE__.{Config, Runtime, Workflow}

  @spec kernel_status() :: map()
  defdelegate kernel_status(), to: Config

  @spec configured_pod() :: map() | nil
  defdelegate configured_pod(), to: Config

  @spec ai_ready?() :: boolean()
  defdelegate ai_ready?(), to: Config

  @spec list_pods() :: [String.t()]
  defdelegate list_pods(), to: Config

  @spec default_repo_path() :: String.t()
  defdelegate default_repo_path(), to: Config

  @spec default_pod_id() :: String.t()
  defdelegate default_pod_id(), to: Config

  @spec ensure_pod(String.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_pod(pod_id, repo_path \\ Config.default_repo_path()) do
    Runtime.ensure_pod(pod_id, repo_path)
  end

  @spec pod_overview(String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate pod_overview(pod_id), to: Runtime

  @spec sync_repo(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def sync_repo(pod_id, repo_path \\ Config.default_repo_path()) do
    Runtime.sync_repo(pod_id, repo_path)
  end

  @spec add_task(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate add_task(pod_id, title, goal), to: Runtime

  @spec select_task(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate select_task(pod_id, task_id), to: Runtime

  @spec plan_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate plan_task(pod_id, task_id), to: Workflow

  @spec draft_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate draft_task(pod_id, task_id), to: Workflow

  @spec review_task(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate review_task(pod_id, task_id), to: Workflow

  @spec chat_with_pod(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate chat_with_pod(pod_id, prompt), to: Workflow

  @spec run_workflow(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate run_workflow(pod_id, task_id), to: Workflow

  @spec reconcile_pod(String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate reconcile_pod(pod_id), to: Runtime

  @spec wake_specialist(String.t(), atom()) :: {:ok, pid()} | {:error, term()}
  defdelegate wake_specialist(pod_id, specialist), to: Runtime
end
