defmodule JidoOSDevWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title><%= assigns[:page_title] || "Jido AgentOS Dev" %></title>
        <link phx-track-static rel="stylesheet" href="/assets/app.css" />
        <script defer phx-track-static src="/phoenix/phoenix.min.js"></script>
        <script defer phx-track-static src="/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script defer phx-track-static src="/assets/app.js"></script>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end
