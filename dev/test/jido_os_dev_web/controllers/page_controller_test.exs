defmodule JidoOSDevWeb.PageControllerTest do
  use JidoOSDevWeb.ConnCase, async: true

  test "GET / renders the repo pod live control plane shell", %{conn: conn} do
    conn = get(conn, "/")
    body = html_response(conn, 200)

    assert body =~ "AgentOS Coding Workflow"
    assert body =~ "Ask the Pod"
    assert body =~ "Workflow Lane"
    assert body =~ "Pod Workspace"
    assert body =~ "Signal Log"
  end
end
