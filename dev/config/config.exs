import Config

config :jido_os_dev,
  ecto_repos: [JidoOSDev.Repo]

config :jido_os_dev, JidoOSDevWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: JidoOSDev.PubSub,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "repopodlive"]

config :jido_os_dev, Jido.AgentOS,
  persistence: [
    adapter: Jido.Ecto.Storage,
    repo: JidoOSDev.Repo
  ]

config :jido_os_dev,
  default_repo_path: Path.expand("../..", __DIR__)

config :jido_ai,
  model_aliases: %{
    fast: "openai:gpt-4.1-mini"
  }

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
