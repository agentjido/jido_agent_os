defmodule JidoOSDev.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :jido_os_dev,
    adapter: Ecto.Adapters.Postgres
end
