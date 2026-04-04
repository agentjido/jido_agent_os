# `jido_ecto` Persistence

`jido_ecto` is the first persistence story for `Jido.AgentOS`.

Recommended kernel config:

```elixir
config :my_app, Jido.AgentOS,
  persistence: [
    adapter: Jido.Ecto.Storage,
    repo: MyApp.Repo
  ]
```

This guide assumes the host application already has:

- an `Ecto.Repo`
- `:ecto_sql`
- a SQL adapter such as `:postgrex`

## Install

Add the dependencies to your host app:

```elixir
{:jido, github: "agentjido/jido", branch: "main", override: true},
{:jido_ecto, github: "agentjido/jido_ecto", branch: "main"},
{:ecto_sql, "~> 3.13"},
{:postgrex, ">= 0.0.0"}
```

If your application already consumes a released Hex version of `:jido`, keep
that source consistent here as well. The important part is that the host app
and `jido_ecto` resolve the same `:jido` source.

## Add A Repo

Create a repo module:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres
end
```

Supervise it before `MyApp.AgentOS` in your application tree.

## Create The Storage Migration

Create a repo migration that freezes the emitted storage DDL:

```elixir
defmodule MyApp.Repo.Migrations.CreateJidoStorage do
  use Ecto.Migration

  def change do
    require Jido.Ecto.Migrations
    Jido.Ecto.Migrations.create_storage_tables(version: 1)
  end
end
```

The `version: 1` value should be kept in the app migration so the generated DDL
stays fixed in your own history.

## Migrate

Run:

```sh
mix ecto.create
mix ecto.migrate
```

## Tables

`version: 1` creates:

- `jido_checkpoints`
- `jido_threads`
- `jido_thread_entries`

## Dev Example

The Phoenix host in
[dev/](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev)
shows this pattern with:

- [repo.ex](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/lib/jido_os_dev/repo.ex)
- [config.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/config/config.exs)
- [dev.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/config/dev.exs)
- [create_jido_storage.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/priv/repo/migrations/20260403160000_create_jido_storage.exs)
