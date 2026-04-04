# Jido.AgentOS

`jido_agent_os` is an OTP-native kernel for running durable Jido pods inside a
host application such as Phoenix.

The mental model is:

- `Jido.Agent` is the unit of behavior
- `Jido.Pod` is the unit of durable agent topology
- `Jido.AgentOS` is the kernel layer that runs pods

## What AgentOS Is For

AgentOS is not primarily about deploying one agent per user session.

AgentOS is for building a long-lived multi-agent backend that can actually do
work over time:

- a coding agent
- a research agent
- a workflow agent
- a multi-agent system that acts as one coherent operational unit

In this model, a pod is the boundary line of a single agent team. A pod is
durable, stateful, and long-lived. Phoenix, or another host app, provides the
shell around that pod: HTTP, LiveView, auth, routing, product UI, and external
APIs.

## What AgentOS Is Not

AgentOS is not primarily:

- a per-user chatbot session framework
- a request-scoped agent launcher
- a chat-first runtime model
- a replacement for `Jido.Agent` or `Jido.Pod`

If chat, sessions, or transport are needed later, they should layer on top of
the kernel instead of defining the kernel.

Pod behavior should extend through normal `Jido.Plugin` modules mounted on the
pod or its member agents. AgentOS does not add a parallel kernel-extension
abstraction on top of Jido's plugin model.

## Core Model

- `Kernel`
  A long-lived `MyApp.AgentOS` host supervised inside a host app.
- `Pod`
  A durable Jido pod managed by a kernel and operated as one coherent unit.
- `Agent`
  A behavioral unit inside a pod.

The preferred public conceptual model is:

```text
Kernel -> Pod -> Agent
```

`Topology` and `Node` remain useful Jido-core concepts, but they should stay as
advanced or internal vocabulary unless graph-level control is actually needed.

## Phoenix Relationship

Phoenix is a host shell around AgentOS, not the thing that defines the pod
model.

In a Phoenix app:

- `MyApp.AgentOS` is the kernel boundary
- pods are the long-lived multi-agent backend
- controllers and LiveViews should usually talk to a domain service or context
  backed by a pod, not to raw pod mechanics directly

That means product routes should generally express domain verbs such as
`submit_task`, `task_status`, or `scale_workers`, while the pod handles the
internal multi-agent coordination behind that boundary. The public app-facing
module can be `MyApp.CodingWorkspace` or `MyApp.SupportDesk`, while the durable
runtime topology underneath remains a pod.

A practical Phoenix layout looks like:

```text
lib/my_app/
  agent_os.ex
  my_app_agents/
    pods/
      coding_pod.ex
    agents/
      planner.ex
      worker.ex
  coding_workspace.ex
  coding_workspace/
    runtime.ex
    prompts.ex
    summary.ex
```

That keeps the public Phoenix context separate from the internal AgentOS
runtime. The context is the stable app-facing API. The pod and member agents
remain internal implementation details.

## Installation

Define a kernel wrapper under your host application's supervision tree:

```elixir
defmodule MyApp.AgentOS do
  use Jido.AgentOS,
    otp_app: :my_app,
    pod: MyApp.AgentOS.Pods.Default
end
```

Then supervise that wrapper:

```elixir
children = [
  {MyApp.AgentOS, []}
]
```

Create and inspect pods on demand:

```elixir
{:ok, pid} = MyApp.AgentOS.ensure_pod("primary")
{:ok, snapshot} = MyApp.AgentOS.pod_snapshot("primary")
```

## Pod Definition

Pods are defined with `Jido.Pod` through the `Jido.AgentOS.Pod` helper. The pod
owns topology; AgentOS does not add a second topology-owning abstraction on top
of it.

```elixir
defmodule MyApp.AgentOS.Pods.Default do
  use Jido.AgentOS.Pod,
    name: "default",
    topology: %{
      intake: %{
        agent: MyApp.AgentOS.Agents.Intake,
        manager: :intake,
        activation: :eager
      },
      worker: %{
        agent: MyApp.AgentOS.Agents.Worker,
        manager: :workers,
        activation: :lazy
      }
    }
end
```

## Persistence

AgentOS persistence is configured at the kernel layer, not on individual pods:

```elixir
config :my_app, Jido.AgentOS,
  persistence: [
    adapter: Jido.Ecto.Storage,
    repo: MyApp.Repo
  ]
```

This keeps the kernel wrapper API stable while allowing different persistence
backends underneath it. Wrapper-specific persistence can still be layered on top
with `config :my_app, MyApp.AgentOS, ...` when needed.

The first concrete persistence guide lives in
[jido_ecto.md](/Users/mhostetler/Source/Jido/proj_jido_os/jido_agent_os/guides/persistence/jido_ecto.md).

## Phoenix Routing Helper

`Jido.AgentOS.Router` provides an optional macro for generic pod routes without
forcing kernel identity into the HTTP shape:

```elixir
import Jido.AgentOS.Router

scope "/api", MyAppWeb do
  pipe_through :api
  pod_routes(controller: PodController)
end

scope "/", MyAppWeb do
  pipe_through :browser
  pod_routes(live: PodLive)
end
```

That expands into a small pod-centric surface such as `GET /api/pods`,
`POST /api/pods/:pod_id`, `GET /api/pods/:pod_id`, and `live "/pods/:pod_id"`.

## Current Spike Shape

The current spike is proving a few things:

- multiple named kernels can run side by side
- kernels can boot and persist durable pods
- pods can expose a coherent operational boundary to a Phoenix host
- dynamic pod mutation is possible without collapsing back into a session model

The `dev/` Phoenix app is the reference host example. It currently runs a
durable `RepoPod` inside one default kernel and exposes it through a
domain-shaped `RepoWorkspace` service. The JSON API and LiveView control plane
call that host service for creating, inspecting, syncing, and operating one
long-lived coding workspace for a local Git checkout.

The repo layout follows the same pattern:

- `dev/lib/jido_os_dev_agents/`: internal durable runtime definitions
- `dev/lib/jido_os_dev/repo_workspace.ex`: public Phoenix context
- `dev/lib/jido_os_dev/repo_workspace/`: context internals

## Design Direction

The design direction for AgentOS is:

- keep the kernel as small as possible
- keep pods durable and long-lived
- keep persistence kernel-scoped by default
- keep chat/session concerns outside the core kernel
- reuse Jido core nouns and data structures instead of inventing duplicates

If AgentOS succeeds, a Phoenix app should be able to host a serious multi-agent
backend as one durable pod per team or domain boundary, not one throwaway agent
per browser session.
