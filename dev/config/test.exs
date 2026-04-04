import Config

config :jido_os_dev, JidoOSDevWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  server: false

config :jido_os_dev, JidoOSDev.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 5432,
  database: "jido_os_dev_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  start: true

config :phoenix, :plug_init_mode, :runtime
