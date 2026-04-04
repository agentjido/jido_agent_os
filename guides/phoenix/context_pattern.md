# Phoenix Context Pattern

`Jido.AgentOS` integrates cleanly with Phoenix when you keep two layers
separate:

- Phoenix context: the public application API
- AgentOS pod: the internal durable runtime

The Phoenix context should own domain verbs such as `submit_task`,
`queue_review`, or `answer_question`. The AgentOS pod should own runtime
topology, durable member agents, and signal routing.

## Recommended Layout

```text
lib/my_app/
  agent_os.ex
  my_app_agents/
    pods/
      coding_pod.ex
    agents/
      planner.ex
      coder.ex
      reviewer.ex
  coding_workspace.ex
  coding_workspace/
    runtime.ex
    prompts.ex
    summary.ex
```

## Responsibilities

- `MyApp.AgentOS`
  Host-supervised kernel wrapper.
- `MyApp.AgentOS.Pods.*`
  Durable pod topology definitions.
- `MyApp.AgentOS.Agents.*`
  Durable member agents that live inside a pod.
- `MyApp.CodingWorkspace`
  Public Phoenix context called by controllers, LiveViews, jobs, and tests.
- `MyApp.CodingWorkspace.Runtime`
  Low-level context internals that translate domain operations into pod, node,
  and signal calls.
- `MyApp.CodingWorkspace.Prompts`
  Prompt construction and other domain-specific orchestration inputs.
- `MyApp.CodingWorkspace.Summary`
  UI/API projections derived from runtime state.

## Why Not Let LiveView Talk To The Pod Directly?

It can, but that is usually the wrong boundary.

If LiveView talks directly to pods and nodes, transport code starts owning:

- signal names and payloads
- node names
- prompt construction
- multi-step orchestration
- state shaping for the UI

That makes topology changes leak into the UI and forces the same logic to be
duplicated across controllers, jobs, tests, and other entry points.

## Why Not Put The Context Into AgentOS?

Because the context is product code, not kernel code.

`Jido.AgentOS` should stay generic: kernel lifecycle, persistence, snapshots,
and pod helpers. The Phoenix context knows your repo, your prompts, your task
verbs, and your UI/API needs. That belongs in the host application.
