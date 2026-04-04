defmodule JidoOSDevAgents do
  @moduledoc """
  Public AgentOS wrapper for the Phoenix dev host.

  This is the one module a host application would normally supervise and call.
  The dev app runs a durable internal `RepoPod` around one local Git checkout
  and exposes that runtime through `JidoOSDev.RepoWorkspace`.
  """

  use Jido.AgentOS,
    otp_app: :jido_os_dev,
    name: :jido_os_dev,
    pod: JidoOSDevAgents.Pods.RepoPod
end
