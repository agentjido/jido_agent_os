defmodule JidoOSDevAgents.Actions.Tools.ListFiles do
  @moduledoc false

  use Jido.Action,
    name: "repo_list_files",
    description: "List tracked files in the active repo checkout.",
    schema: [
      limit: [type: :integer, default: 30]
    ]

  @impl true
  def run(%{limit: limit}, context) do
    with {:ok, repo_path} <- repo_path(context),
         {:ok, files} <- JidoOSDev.RepoCheckout.tracked_files(repo_path, limit: max(limit, 1)) do
      {:ok, %{files: files, count: length(files), repo_path: repo_path}}
    end
  end

  defp repo_path(context) do
    path =
      context[:repo_path] ||
        get_in(context, [:repo, :repo_path]) ||
        get_in(context, [:repo, :path]) ||
        get_in(context, [:tool_context, :repo_path]) ||
        get_in(context, [:tool_context, "repo_path"]) ||
        get_in(context, [:tool_context, :repo, :repo_path]) ||
        get_in(context, [:tool_context, :repo, :path])

    if is_binary(path) and String.trim(path) != "" do
      {:ok, path}
    else
      {:error, :missing_repo_path}
    end
  end
end
