defmodule Jido.AgentOSKernelConfigTest do
  use ExUnit.Case, async: false

  test "resolve_kernel_opts merges shared config, wrapper config, and kernel overrides" do
    shared_before = Application.get_env(:jido_agent_os, Jido.AgentOS)
    wrapper_before = Application.get_env(:jido_agent_os, Jido.AgentOSTestWrapper)

    on_exit(fn ->
      restore_env(:jido_agent_os, Jido.AgentOS, shared_before)
      restore_env(:jido_agent_os, Jido.AgentOSTestWrapper, wrapper_before)
    end)

    Application.put_env(:jido_agent_os, Jido.AgentOS,
      persistence: [adapter: Jido.AgentOSKernelConfigTest.SharedStorage, prefix: "shared"]
    )

    Application.put_env(
      :jido_agent_os,
      Jido.AgentOSTestWrapper,
      pod: Jido.AgentOSKernelConfigTest.WrapperPod,
      persistence: [repo: Jido.AgentOSKernelConfigTest.WrapperRepo]
    )

    opts =
      Jido.AgentOS.resolve_kernel_opts(
        Jido.AgentOSTestWrapper,
        :jido_agent_os,
        [name: :default_kernel, pod: Jido.AgentOSKernelConfigTest.DefaultPod],
        name: :kernel_override,
        persistence: [timeout: 5_000]
      )

    assert opts[:name] == :kernel_override
    assert opts[:pod] == Jido.AgentOSKernelConfigTest.WrapperPod
    assert opts[:persistence][:adapter] == Jido.AgentOSKernelConfigTest.SharedStorage
    assert opts[:persistence][:repo] == Jido.AgentOSKernelConfigTest.WrapperRepo
    assert opts[:persistence][:prefix] == "shared"
    assert opts[:persistence][:timeout] == 5_000
  end

  defmodule DefaultPod do
  end

  defmodule WrapperPod do
  end

  defmodule SharedStorage do
  end

  defmodule WrapperRepo do
  end

  defmodule Jido.AgentOSTestWrapper do
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
