defmodule JidoOSDevAgents.Actions.Repo.SyncCheckout do
  @moduledoc false

  use Jido.Action,
    name: "repo_sync_checkout",
    description: "Inspect a local git checkout and refresh repo state.",
    schema: [
      repo_path: [type: :string, required: true]
    ]

  alias Jido.Agent.StateOp

  @impl true
  def run(%{repo_path: repo_path}, _context) do
    case JidoOSDev.RepoCheckout.inspect_checkout(repo_path) do
      {:ok, repo} ->
        {:ok, repo,
         StateOp.set_state(%{
           repo_path: repo.path,
           repo_name: repo.repo_name,
           branch: repo.branch,
           head: repo.head,
           dirty: repo.dirty,
           changed_files: repo.changed_files,
           file_count: repo.file_count,
           changed_count: repo.changed_count,
           last_scan_at: repo.scanned_at
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
