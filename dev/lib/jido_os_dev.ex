defmodule JidoOSDev do
  @moduledoc """
  Reference Phoenix host for `Jido.AgentOS`.

  This app keeps the canonical host boundary small:

  - `JidoOSDevAgents` is the kernel wrapper the app supervises.
  - `JidoOSDevAgents.*` holds the internal durable runtime topology.
  - `JidoOSDev.RepoWorkspace` is the Phoenix context backed by that runtime.
  - `JidoOSDev.RepoWorkspace.*` holds the context's internal orchestration modules.
  - `JidoOSDev.RepoCheckout` is the local Git checkout adapter.
  - `JidoOSDev.ObservabilityLog` is host-level observability glue for the demo UI.
  """
end
