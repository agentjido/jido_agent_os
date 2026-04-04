# AGENTS

## Intent

`jido_agent_os` defines the kernel layer for running pods.

It is not a replacement for `Jido.Agent` or `Jido.Pod`. Those remain the core
behavioral and topological primitives provided by Jido itself.

AgentOS exists one layer above them:

- Jido core defines agents, pods, topology, signals, and instructions
- AgentOS defines kernels and persistence around those pod primitives

The intended use case is not "deploy an agent per user session."

The intended use case is:

- build a long-lived agent backend inside a host application such as Phoenix
- use Jido primitives to compose a durable multi-agent pod
- operate that pod as one coherent unit through an OTP-native kernel

In that sense, AgentOS is the host/runtime layer for an "open claw":

- a coding agent
- a research agent
- a workflow agent
- a multi-agent backend that can actually do work over time

## Definition

Jido AgentOS is a Kernel for running pods.

An AgentOS pod is the boundary line of a single agent team.

A pod is not an ephemeral chat session or a request-scoped worker. A pod is a
durable, long-lived, stateful system made up of multiple agents that act as one
coherent operational unit.

AgentOS is an embeddable OTP kernel for:

- hosting one or more named kernels inside a host application
- starting and supervising pods inside those kernels
- attaching kernel-scoped persistence
- providing a stable operational API for host applications such as Phoenix

In short:

- `Jido.Agent` is the unit of behavior
- `Jido.Pod` is the unit of durable agent topology
- `Jido.AgentOS` is the kernel layer that runs pods

Another way to say it:

- a kernel runs pods
- a pod contains agents
- a pod is the durable operational boundary of an agent system

The phrase "Agent System" is descriptive language in this package, not a
separate first-class runtime abstraction. AgentOS should prefer existing Jido
core nouns like `Pod`, `Agent`, and `Topology` instead of inventing new
duplicates.

## Core Model

### Jido Core

- `Agent`
  A pure `Jido.Agent` data structure with immutable state and `cmd/2`.
- `Pod`
  A `Jido.Pod` wrapping a canonical durable topology.
- `Topology`
  A `Jido.Pod.Topology` graph of named nodes and edges.
- `Node`
  A `Jido.Pod.Topology.Node` entry inside a topology.

### AgentOS

- `Kernel`
  A named `Jido.AgentOS` host supervised inside a host app such as Phoenix.
  This is the long-lived operational boundary.
- `Pod`
  The durable, long-lived agent team a kernel runs and operates as one unit.
  Pods are defined with `Jido.Pod` / `Jido.AgentOS.Pod`, not with a separate
  AgentOS-local "system" abstraction.
- `Persistence`
  Kernel-scoped storage configuration for pods and related durable state.

## Glossary

- kernel: the long-lived named AgentOS host
- pod: the durable, stateful Jido pod object managed by a kernel
- agent team: a descriptive phrase for the agents contained inside one pod
- plugin: a standard `Jido.Plugin` extension mounted on a pod or agent

## Boundaries

- Keep the kernel as small as possible.
- Do not move chat, sessions, or LLM assumptions into the core kernel.
- Do not model pods as ephemeral user sessions.
- Do not treat "one request" or "one browser session" as the natural pod
  boundary.
- Keep persistence kernel-scoped, not pod-scoped by default.
- Treat `Jido.Plugin` as the extension point for pod behavior.
- Reuse Jido core data structures where they already exist instead of inventing AgentOS-local duplicates.
- Treat `Topology` and `Node` as advanced or internal vocabulary unless a task genuinely needs graph-level control.

## Phoenix Relationship

Phoenix is a host shell around AgentOS, not the thing that defines the pod
model.

In a Phoenix app:

- Phoenix provides HTTP, LiveView, auth, routing, and product UI
- `MyApp.AgentOS` provides the kernel host boundary
- pods provide the long-lived multi-agent backend

Routes and LiveViews should usually target pod-level operations and product
verbs, not raw agent internals. A Phoenix route should generally talk to a pod
as one coherent unit, even if that pod contains many agents internally.

## Non-Goals

AgentOS is not primarily:

- a per-user chatbot session framework
- a request-scoped agent launcher
- a chat-first runtime model
- a replacement for `Jido.Agent` or `Jido.Pod`

## Project Shape

- `lib/jido/agent_os.ex`
  Kernel host API and wrapper macro.
- `lib/jido/agent_os/pod.ex`
  AgentOS pod-definition helper built on top of `Jido.Pod`.
- `lib/jido/agent_os/persistence.ex`
  Kernel persistence configuration.
- `lib/jido/agent_os/router.ex`
  Optional Phoenix routing helper for generic pod routes.
- `dev/`
  Phoenix host example and integration surface.

## Current Status

- The preferred public conceptual model is `Kernel -> Pod -> Agent`.
- Pods are durable, long-lived, stateful agent teams, not session objects.
- Phoenix should integrate around pod boundaries, not replace them.
- The codebase should use `kernel` and `pod` as the primary AgentOS nouns.
- `Topology` and `Node` remain advanced Jido-core vocabulary when graph-level control is needed.
