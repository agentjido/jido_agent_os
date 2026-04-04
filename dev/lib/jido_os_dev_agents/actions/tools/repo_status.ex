defmodule JidoOSDevAgents.Actions.Tools.RepoStatus do
  @moduledoc false

  use Jido.Action,
    name: "repo_status",
    description: "Return the current repo checkout summary for the active coding pod.",
    schema: []

  @impl true
  def run(_params, context) do
    case repo_from_context(context) do
      %{repo_path: repo_path} = repo when is_binary(repo_path) and repo_path != "" ->
        {:ok, repo}

      %{path: repo_path} when is_binary(repo_path) and repo_path != "" ->
        JidoOSDev.RepoCheckout.inspect_checkout(repo_path)

      _ ->
        {:error, :missing_repo_context}
    end
  end

  defp repo_from_context(context) do
    context[:repo] ||
      get_in(context, [:tool_context, :repo]) ||
      get_in(context, [:tool_context, "repo"]) ||
      %{}
  end
end
