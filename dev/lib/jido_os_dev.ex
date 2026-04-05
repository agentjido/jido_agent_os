defmodule JidoOSDev do
  @moduledoc """
  Reference Phoenix host for `Jido.AgentOS`.

  This app uses three top-level peer namespaces:

  - `JidoOSDev`: contexts, adapters, and application-facing code
  - `JidoOSDevWeb`: HTTP and LiveView transport
  - `JidoOSDevAgents`: durable agent runtime built on `Jido.AgentOS`

  The public application boundary stays in `JidoOSDev.RepoWorkspace`. The
  runtime boundary stays in `JidoOSDevAgents`.
  """
end
