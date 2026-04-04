defmodule JidoOSDev.RepoWorkspace.Config do
  @moduledoc false

  alias Jido.AgentOS.Pod, as: AgentOSPod

  @spec kernel_status() :: map()
  def kernel_status, do: JidoOSDevAgents.kernel_status()

  @spec configured_pod() :: map() | nil
  def configured_pod do
    JidoOSDevAgents.pod()
    |> AgentOSPod.summary()
  end

  @spec ai_ready?() :: boolean()
  def ai_ready?, do: configured_ai_ready?()

  @spec list_pods() :: [String.t()]
  def list_pods, do: JidoOSDevAgents.list_pods()

  @spec default_repo_path() :: String.t()
  def default_repo_path do
    configured =
      :jido_os_dev
      |> Application.get_env(:default_repo_path, File.cwd!())
      |> Path.expand()

    [configured, Path.join(configured, "deps/jido"), Path.join(configured, "deps/jido_ai")]
    |> Enum.uniq()
    |> Enum.find_value(configured, fn path ->
      case JidoOSDev.RepoCheckout.inspect_checkout(path) do
        {:ok, repo} -> repo.path
        {:error, _reason} -> false
      end
    end)
  end

  @spec default_pod_id() :: String.t()
  def default_pod_id do
    case list_pods() do
      [pod_id | _rest] -> pod_id
      [] -> JidoOSDev.RepoCheckout.default_pod_id(default_repo_path())
    end
  end

  defp configured_ai_ready? do
    case Application.get_env(:req_llm, :openai_api_key) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end
end
