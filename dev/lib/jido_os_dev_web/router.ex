defmodule JidoOSDevWeb.Router do
  use JidoOSDevWeb, :router

  import Jido.AgentOS.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {JidoOSDevWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", JidoOSDevWeb do
    pipe_through(:browser)

    live("/", RepoPodLive, :index)
    pod_routes(live: RepoPodLive)
  end

  scope "/api", JidoOSDevWeb do
    pipe_through(:api)

    pod_routes(controller: PodController)
  end
end
