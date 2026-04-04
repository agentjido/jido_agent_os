defmodule JidoOSDevAgents.Actions.Tools.ReadFile do
  @moduledoc false

  use Jido.Action,
    name: "repo_read_file",
    description: "Read one file from the active repo checkout.",
    schema: [
      path: [type: :string, required: true],
      max_chars: [type: :integer, default: 8_000]
    ]

  @impl true
  def run(%{path: path, max_chars: max_chars}, context) do
    with {:ok, repo_path} <- repo_path(context),
         {:ok, file} <-
           JidoOSDev.RepoCheckout.read_file(repo_path, path, max_chars: max(max_chars, 256)) do
      {:ok, Map.put(file, :repo_path, repo_path)}
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
