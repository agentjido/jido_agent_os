defmodule JidoOSDevWeb.PodController do
  use JidoOSDevWeb, :controller

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    json(conn, %{
      pods: JidoOSDev.RepoWorkspace.list_pods(),
      default_repo_path: JidoOSDev.RepoWorkspace.default_repo_path()
    })
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"pod_id" => pod_id} = params) do
    repo_path = Map.get(params, "repo_path", JidoOSDev.RepoWorkspace.default_repo_path())

    with {:ok, _pid} <- JidoOSDev.RepoWorkspace.ensure_pod(pod_id, repo_path),
         {:ok, overview} <- JidoOSDev.RepoWorkspace.pod_overview(pod_id) do
      json(conn, %{pod: serialize_overview(overview)})
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"pod_id" => pod_id}) do
    case JidoOSDev.RepoWorkspace.pod_overview(pod_id) do
      {:ok, overview} ->
        json(conn, %{pod: serialize_overview(overview)})

      {:error, :pod_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "pod_not_found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp serialize_overview(overview) do
    %{
      pod_id: overview.pod.pod_id,
      pod: overview.pod.pod,
      topology_name: overview.pod.topology_name,
      nodes: overview.pod.nodes,
      node_snapshots: overview.pod.node_snapshots,
      pid: inspect(overview.pod.pid),
      repo: overview.repo,
      task_board: overview.task_board,
      specialists:
        Map.new(overview.specialists, fn {name, specialist} ->
          {name, specialist}
        end),
      kernel: %{
        kernel_name: overview.kernel.kernel_name,
        supervisor: inspect(overview.kernel.supervisor),
        pods: overview.kernel.pods
      },
      ai_ready: overview.ai_ready
    }
  end
end
