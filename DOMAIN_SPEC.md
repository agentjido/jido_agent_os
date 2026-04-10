# DOMAIN_SPEC

This document captures an idea for a missing authoring layer in AgentOS.

It is not a working implementation. It is a design note intended to make the
concept easy to pick up later.

## Short Version

AgentOS already has a strong runtime story:

- `Jido.Agent` is the unit of behavior
- `Jido.Pod` is the unit of durable topology
- `Jido.AgentOS` is the kernel that runs pods

What still feels incomplete is the application authoring story above the pod.

In practice, Phoenix and other host apps want a stable public module that wraps
the pod and exposes domain operations such as:

- `open_run/1`
- `status/1`
- `submit_task/2`
- `sync_repo/1`
- `publish/1`

That missing piece is what this document calls `Domain`.

## Core Idea

`Domain` is the application-facing boundary above a pod.

The intended conceptual stack becomes:

```text
Phoenix / Host App -> Domain -> Pod -> Agent
                     \-> AgentOS Kernel
```

More precisely:

- Phoenix provides HTTP, LiveView, auth, routing, and product UI
- `Jido.AgentOS` provides the kernel host layer
- `Domain` provides the stable application API
- `Pod` provides the durable runtime topology
- `Agent` provides the behavioral units inside the pod

This means the host application should not need to talk directly to raw pod
mechanics or raw signals for common operations.

## Why Domain Feels Necessary

AgentOS README already points in this direction:

- Phoenix should usually talk to a domain service or context backed by a pod
- the public app-facing module might be `MyApp.CodingWorkspace`
- the pod remains the durable runtime underneath

That is already the right instinct.

What is missing is a formal construct that gives that layer a name and shape.

Without `Domain`, every app has to hand-roll:

- one public API/context module
- one pod module
- a few policy/helper modules
- a rationale for when to use signals directly vs when not to

`Domain` would formalize that pattern.

## What Domain Is

`Domain` is not a new runtime.

It is not a replacement for `Pod`.

It is not a replacement for `Kernel`.

It is a higher-level authoring model for building a complete AgentOS-backed
application boundary.

Think of it like:

- Phoenix context
- plus app-facing service boundary
- plus generated pod facade
- plus explicit places for policy and workflow artifacts

## Responsibilities

A `Domain` should own:

- the public app-facing command/query API
- orchestration that spans multiple pod/runtime calls
- ingress translation from product events into pod protocol
- policy modules or inline policy logic
- workflow artifacts / projections / memory-thread shaping
- lifecycle hooks such as fresh-run initialization and shutdown cleanup

A `Domain` should not replace:

- pod topology
- agent behavior
- kernel boot and persistence

## Signals vs Domain API

Signals should remain important.

They are still the wire protocol for:

- ingress events
- inter-agent communication
- child-to-parent communication
- external dispatch and routing

But signals are not sufficient as the only host-app API because they expose:

- protocol names
- transport metadata
- routing details
- multi-step choreography

Host apps need semantic operations instead:

- `RepoWorkspace.sync/1`
- `CodingWorkspace.submit_task/2`
- `SupportDesk.status/1`

So the rule should be:

- signals are the internal protocol
- domain commands and queries are the public app API

## Relationship To Existing AgentOS Concepts

### Kernel

The kernel remains the host/runtime boundary.

It starts managers, scopes persistence, and provides pod-level operations.

### Pod

The pod remains the durable operational unit.

It owns the topology and runtime coordination of its internal agents.

### Domain

The domain sits above the pod and below Phoenix.

It wraps pod operations in application semantics.

## Proposed Module Layout

In a Phoenix app, the preferred layout could become:

```text
lib/
  my_app.ex
  my_app/
    coding_workspace.ex
    coding_workspace/
      pod.ex
      policy.ex
      artifacts.ex
      agents/
      actions/
      sensors/
  my_app_web.ex
  my_app_web/
    ...
  my_app_agent_os.ex
```

This is the same shape already emerging informally, but with a stronger
convention:

- `MyApp.CodingWorkspace` is the domain
- `MyApp.CodingWorkspace.Pod` is the pod
- nested policy/artifact modules are domain internals
- `MyApp.AgentOS` is the kernel host

## Proposed API Direction

There are two possible levels of ambition.

### 1. Thin Macro / Convention Layer

Example:

```elixir
defmodule MyApp.CodingWorkspace do
  use Jido.AgentOS.Domain,
    name: "coding_workspace",
    manager: :coding_workspaces

  alias __MODULE__.Pod

  def sync(run, opts \\ []) do
    dispatch_to_pod(run, "repo.sync.requested", %{}, opts)
  end

  def status(run) do
    # domain-specific query shape
  end
end

defmodule MyApp.CodingWorkspace.Pod do
  use Jido.AgentOS.Pod,
    name: "coding_workspace",
    topology: %{...}
end
```

This version mostly standardizes:

- where the public module lives
- how it references the nested pod
- common pod wrapper functions
- common signal helpers

### 2. Real DSL

This is the more ambitious direction, and likely the more interesting one.

Example:

```elixir
defmodule MyApp.CodingWorkspace do
  use Jido.AgentOS.Domain,
    name: "coding_workspace",
    manager: :coding_workspaces

  commands do
    command :open_run, params: [workspace_id: :string]
    command :sync_repo
    command :run_task, params: [task: :map]
    command :publish_result
  end

  queries do
    query :status
    query :timeline
    query :artifacts
    query :topology
  end

  lifecycle do
    mount do
      {:ok, %{workspace_mode: :repo}}
    end

    shutdown do
      :ok
    end
  end

  pod do
    agent :repo_state, MyApp.CodingWorkspace.Agents.RepoState,
      registry: :repo_state_agents,
      activation: :eager

    agent :planner, MyApp.CodingWorkspace.Agents.Planner,
      registry: :planner_agents,
      activation: :lazy,
      depends_on: [:repo_state]

    pod :analysis, MyApp.RepoAnalysis,
      registry: :repo_analysis_runs,
      activation: :lazy,
      key: &"repo:" <> &1.repo

    ref :knowledge_base, MyApp.KnowledgeBase,
      registry: :knowledge_base_runs,
      key: & &1.repo
  end

  ingress do
    sensor MyApp.Sensors.RepoWebhook,
      as: :repo_webhook,
      config: %{source_path: "/webhooks/repo"}
  end

  policy do
    def needs_replan?(state), do: ...
  end

  artifacts do
    record :repo_synced, memory: [...], thread: ...
    record :task_completed, memory: [...], thread: ...
  end

  routes do
    on "repo.webhook.received" do
      project :repo_synced
      send_to :planner, "workspace.plan.requested"
    end
  end
end
```

This would be documentation-first for now, not a commitment to exact syntax.

## Nested Pods vs External References

If `Domain` becomes a real DSL, it should distinguish between:

### `pod`

An owned nested pod.

- the domain is responsible for acquiring it
- the domain may reconcile it as part of workflow execution
- it participates in the domain's runtime composition

### `ref`

A referenced external pod.

- the domain can signal/query it
- the domain does not own its lifecycle

That keeps composition and integration distinct.

## Where This Probably Belongs

This idea feels more native to AgentOS than to Jido core.

Reason:

- Jido core should likely remain the primitives layer
- AgentOS is already the host-facing layer that talks about Phoenix, contexts,
  kernels, and long-lived operational backends
- `Domain` is exactly the missing authoring layer in that stack

So the likely progression is:

1. incubate `Domain` in AgentOS
2. use it to prove the host-app authoring model
3. later decide whether it stays AgentOS-specific or graduates into a broader
   Jido package

## Macro vs Spark DSL

### Local Macro

Good if the goal is:

- bless the convention
- generate the boring pod wrapper functions
- keep implementation light at first

### Spark DSL

Good if the goal is:

- a serious authoring system
- nested sections like `commands`, `queries`, `pod`, `policy`, `artifacts`
- compile-time validation
- introspection and future code generation

Current instinct:

- if `Domain` is just a convention, a local macro is enough
- if `Domain` is the major conceptual leap for AgentOS, Spark is likely the
  right long-term tool

## Open Questions

- Should the name be `Jido.AgentOS.Domain` or simply `Jido.Domain` within this repo?
- Should v1 be a thin macro or go straight to a Spark DSL?
- Should `policy` and `artifacts` be real DSL sections, or just naming
  conventions around nested modules?
- Should nested pods and external refs be in v1 or follow later?
- Should the public API be generated commands/queries, or hand-written
  functions with helper generation underneath?
- Should the domain layer own mount/shutdown semantics even before Jido core has
  first-class pod runtime callbacks?

## Practical Next Step

The next useful spike is probably:

1. create a small `Jido.AgentOS.Domain` experiment
2. implement only:
   - metadata
   - nested pod convention
   - generated pod wrapper functions
3. rewrite one AgentOS dev example around it
4. decide from real usage whether Spark is justified

## Summary

`Domain` appears to be the missing piece in AgentOS.

It would give AgentOS a complete authoring stack:

- Kernel
- Domain
- Pod
- Agent

That would finally give host apps a stable answer to:

- what object am I building?
- where do I put the logic?
- how should Phoenix interact with a pod-backed backend?
