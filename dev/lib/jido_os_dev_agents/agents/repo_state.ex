defmodule JidoOSDevAgents.Agents.RepoState do
  @moduledoc false

  use Jido.Agent,
    name: "repo_pod_repo_state",
    signal_routes: [
      {"repo.sync", JidoOSDevAgents.Actions.Repo.SyncCheckout}
    ],
    schema: [
      repo_path: [type: :string, default: ""],
      repo_name: [type: :string, default: ""],
      branch: [type: :string, default: ""],
      head: [type: :string, default: ""],
      dirty: [type: :boolean, default: false],
      changed_files: [type: {:list, :any}, default: []],
      file_count: [type: :integer, default: 0],
      changed_count: [type: :integer, default: 0],
      last_scan_at: [type: :string, default: ""]
    ]
end
