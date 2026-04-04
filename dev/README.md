# Jido.AgentOS Dev Host

Minimal Phoenix host application that embeds one default `Jido.AgentOS` kernel
and a first `jido_ecto` persistence scaffold.

The example pod is `JidoOSDev.AgentOS.Pods.RepoPod`, a durable coding pod for
one local Git checkout. It keeps two eager state agents warm (`repo_state`,
`task_board`) and wakes three lazy `Jido.AI.Agent` specialists (`planner`,
`coder`, `reviewer`) when needed.

## Run

### Start PostgreSQL

```sh
docker compose up -d postgres
```

### Install And Migrate

```sh
mix setup
```

This runs:

```sh
mix deps.get
mix ecto.create
mix ecto.migrate
```

### Start Phoenix

```sh
mix phx.server
```

### Optional AI Setup

If you want the planner, coder, and reviewer agents to run real
`Jido.AI.Agent` passes, copy the example env file and add an OpenAI key:

```sh
cp .env.example .env
```

Then set `OPENAI_API_KEY` in `.env` and restart Phoenix.

You can also set `JIDO_OS_DEV_REPO_PATH` in `.env` if you want the Repo Pod to
default to a different local Git checkout.

## Endpoints

- `GET /` renders the Repo Pod control plane
- `GET /api/pods` lists started pods
- `POST /api/pods/:pod_id` ensures a pod exists
- `GET /api/pods/:pod_id` returns a pod snapshot
- `GET /pods/:pod_id` renders the pod control plane directly

The Phoenix app talks to the backend wrapper module `JidoOSDev.AgentOS`.
The dev host starts one wrapper-backed default kernel:
`{JidoOSDev.AgentOS, []}`.

## Persistence

Kernel persistence is configured at the top level in
[config.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/config/config.exs)
under `Jido.AgentOS`, while the PostgreSQL repo itself lives in
[repo.ex](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/lib/jido_os_dev/repo.ex)
and is configured in
[dev.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/config/dev.exs).

The storage tables come from
[create_jido_storage.exs](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/dev/priv/repo/migrations/20260403160000_create_jido_storage.exs),
which uses `Jido.Ecto.Migrations.create_storage_tables(version: 1)`.
