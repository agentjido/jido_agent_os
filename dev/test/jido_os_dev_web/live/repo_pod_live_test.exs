defmodule JidoOSDevWeb.RepoPodLiveTest do
  use JidoOSDevWeb.ConnCase, async: false

  test "the root layout includes the LiveView client assets", %{conn: conn} do
    html = conn |> get("/") |> html_response(200)

    assert html =~ "/assets/app.css"
    assert html =~ "/assets/app.js"
    assert html =~ "/phoenix/phoenix.min.js"
    assert html =~ "/phoenix_live_view/phoenix_live_view.min.js"
  end

  test "the control plane can create a repo workspace and queue a coding task", %{conn: conn} do
    pod_id = "live-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, view, html} = live(conn, "/")

    assert html =~ "AgentOS Coding Workflow"
    assert html =~ "Ask the Pod"

    view
    |> element("form[phx-submit=ensure-pod]")
    |> render_submit(%{
      "pod" => %{"id" => pod_id, "repo_path" => JidoOSDev.RepoWorkspace.default_repo_path()}
    })

    assert render(view) =~ pod_id
    assert render(view) =~ "Signal Log"

    view
    |> element("form[phx-submit=add-task]")
    |> render_submit(%{
      "task" => %{
        "title" => "Plan a repo improvement",
        "goal" => "Describe one useful improvement to the repo coding workspace."
      }
    })

    rendered = render(view)

    assert rendered =~ "Plan a repo improvement"
    assert rendered =~ "Queued coding task."
    assert rendered =~ "Workflow Lane"
  end

  test "the pod route loads the selected repo workspace control plane", %{conn: conn} do
    pod_id = "repo-route-" <> Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, _pid} =
             JidoOSDev.RepoWorkspace.ensure_pod(
               pod_id,
               JidoOSDev.RepoWorkspace.default_repo_path()
             )

    {:ok, _view, html} = live(conn, "/pods/#{pod_id}")

    assert html =~ pod_id
    assert html =~ "Ask the Pod"
    assert html =~ "Signal Log"
  end
end
