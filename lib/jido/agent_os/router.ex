defmodule Jido.AgentOS.Router do
  @moduledoc """
  Optional Phoenix router helper for generic AgentOS pod routes.

  This macro expands into a small pod-centric control-plane surface. It is
  intentionally limited to generic pod lifecycle and inspection routes so host
  applications can keep product-specific routes separate.

  ## Examples

      import Jido.AgentOS.Router

      scope "/api", MyAppWeb do
        pipe_through :api
        pod_routes(controller: PodController)
      end

      scope "/", MyAppWeb do
        pipe_through :browser
        pod_routes(live: PodLive)
      end

  Supported options:

  - `:controller` - controller module for `GET /pods`, `POST /pods/:pod_id`,
    and `GET /pods/:pod_id`
  - `:live` - LiveView module for the pod control plane
  - `:path` - base API path, defaults to `"/pods"`
  - `:live_path` - live route path, defaults to `"/pods/:pod_id"`
  """

  defmacro pod_routes(opts \\ []) do
    controller = Keyword.get(opts, :controller)
    live_view = Keyword.get(opts, :live)
    path = Keyword.get(opts, :path, "/pods")
    live_path = Keyword.get(opts, :live_path, "/pods/:pod_id")

    routes =
      []
      |> maybe_append_controller_routes(controller, path)
      |> maybe_append_live_route(live_view, live_path)

    quote do
      (unquote_splicing(routes))
    end
  end

  defp maybe_append_controller_routes(routes, nil, _path), do: routes

  defp maybe_append_controller_routes(routes, controller, path) do
    routes ++
      [
        quote do
          get(unquote(path), unquote(controller), :index)
        end,
        quote do
          post(unquote(path) <> "/:pod_id", unquote(controller), :create)
        end,
        quote do
          get(unquote(path) <> "/:pod_id", unquote(controller), :show)
        end
      ]
  end

  defp maybe_append_live_route(routes, nil, _live_path), do: routes

  defp maybe_append_live_route(routes, live_view, live_path) do
    routes ++
      [
        quote do
          live(unquote(live_path), unquote(live_view), :show)
        end
      ]
  end
end
