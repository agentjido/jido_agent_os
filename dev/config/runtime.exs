import Config

env_file = Path.expand("../.env", __DIR__)

if File.exists?(env_file) do
  env_vars = Dotenvy.source!([env_file, System.get_env()])
  System.put_env(env_vars)
end

config :jido_os_dev,
  default_repo_path:
    System.get_env("JIDO_OS_DEV_REPO_PATH") ||
      Application.get_env(:jido_os_dev, :default_repo_path)

config :req_llm,
  openai_api_key: System.get_env("OPENAI_API_KEY")
