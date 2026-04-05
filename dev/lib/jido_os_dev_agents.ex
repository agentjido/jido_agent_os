defmodule JidoOSDevAgents do
  @moduledoc """
  Durable agent runtime subsystem for the Phoenix dev host.

  This root sits beside `JidoOSDev` and `JidoOSDevWeb` as a peer subsystem,
  much like Phoenix treats `MyAppWeb` as distinct from `MyApp`.

  It owns the internal runtime boundary for the example app:

  - the `Jido.AgentOS` kernel wrapper
  - durable pod definitions
  - member agents
  - signal-driven actions

  Phoenix transport and contexts do not call pods and agents directly. They go
  through `JidoOSDev.RepoWorkspace`, which uses this subsystem internally.
  """

  use Jido.AgentOS,
    otp_app: :jido_os_dev,
    name: :jido_os_dev,
    pod: JidoOSDevAgents.Pods.RepoPod
end
