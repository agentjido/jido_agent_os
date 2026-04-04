defmodule JidoOSDevWeb.PodControllerTest do
  use JidoOSDevWeb.ConnCase, async: false

  test "GET /api/pods lists pod ids", %{conn: conn} do
    conn = get(conn, "/api/pods")

    assert %{"pods" => pods} = json_response(conn, 200)
    assert is_list(pods)
  end

  test "POST /api/pods/:pod_id creates a pod and exposes it via the API", %{conn: conn} do
    pod_id = "api-" <> Integer.to_string(System.unique_integer([:positive]))
    repo_name = JidoOSDev.RepoWorkspace.default_repo_path() |> Path.basename()

    conn = post(conn, "/api/pods/#{pod_id}")

    assert %{
             "pod" => %{
               "pod_id" => ^pod_id,
               "pod" => %{"name" => "repo_pod"},
               "repo" => %{"repo_name" => ^repo_name}
             }
           } = json_response(conn, 200)

    conn = build_conn() |> get("/api/pods")

    assert %{"pods" => pods} = json_response(conn, 200)
    assert pod_id in pods
  end

  test "GET /api/pods/:pod_id returns a pod snapshot", %{conn: conn} do
    pod_id = "show-" <> Integer.to_string(System.unique_integer([:positive]))
    _conn = post(conn, "/api/pods/#{pod_id}")

    conn = build_conn() |> get("/api/pods/#{pod_id}")

    assert %{
             "pod" => %{
               "pod_id" => ^pod_id,
               "pod" => %{"name" => "repo_pod"},
               "nodes" => nodes
             }
           } = json_response(conn, 200)

    assert "repo_state" in nodes
  end
end
