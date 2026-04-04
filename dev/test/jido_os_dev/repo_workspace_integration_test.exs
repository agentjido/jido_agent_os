defmodule JidoOSDev.RepoWorkspaceIntegrationTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _started} = Application.ensure_all_started(:jido_os_dev)
    :ok
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(JidoOSDev.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(JidoOSDev.Repo, {:shared, self()})
    :ok
  end

  test "the default kernel runs durable repo workspaces for local checkouts" do
    pod_id = "repo-" <> Integer.to_string(System.unique_integer([:positive]))
    repo_path = JidoOSDev.RepoWorkspace.default_repo_path()

    assert {:ok, pod_pid} = JidoOSDev.RepoWorkspace.ensure_pod(pod_id, repo_path)
    assert {:ok, same_pid} = JidoOSDev.RepoWorkspace.ensure_pod(pod_id, repo_path)
    assert pod_pid == same_pid

    assert {:ok, overview} = JidoOSDev.RepoWorkspace.pod_overview(pod_id)

    assert overview.kernel.kernel_name == :jido_os_dev
    assert overview.pod.pod.name == "repo_pod"
    assert overview.repo.repo_name == Path.basename(repo_path)
    assert overview.repo.branch
    assert length(overview.pod.nodes) == 6
    assert "assistant" in overview.pod.nodes
    assert "repo_state" in overview.pod.nodes
    assert "task_board" in overview.pod.nodes
    assert "planner" in overview.pod.nodes
    assert "coder" in overview.pod.nodes
    assert "reviewer" in overview.pod.nodes

    assert {:ok, task_board} =
             JidoOSDev.RepoWorkspace.add_task(
               pod_id,
               "Explain the repo workspace",
               "Summarize how the durable repo workspace is structured."
             )

    assert length(task_board.tasks) == 1
    assert hd(task_board.tasks).title == "Explain the repo workspace"
  end
end
