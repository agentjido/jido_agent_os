import Config

config :jido_os_dev, JidoOSDevWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  server: true

config :jido_os_dev, JidoOSDev.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 5432,
  database: "jido_os_dev_dev",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool_size: 10,
  start: true
