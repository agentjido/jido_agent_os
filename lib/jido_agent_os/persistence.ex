defmodule Jido.AgentOS.Persistence do
  @moduledoc """
  Normalized kernel persistence configuration.

  Persistence is configured at the AgentOS kernel layer, not on individual
  systems. The common host-level shape is:

      config :my_app, Jido.AgentOS,
        persistence: [
          adapter: Jido.Ecto.Storage,
          repo: MyApp.Repo
        ]

  This keeps the kernel host API (`MyApp.AgentOS`) separate from the storage
  backend being used underneath it. A different backend can swap in by changing
  the configured adapter and options.
  """

  @enforce_keys [:adapter, :options, :storage]
  defstruct [:adapter, :options, :storage]

  @type storage_tuple :: {module(), keyword()}

  @type t :: %__MODULE__{
          adapter: module(),
          options: keyword(),
          storage: storage_tuple()
        }

  @doc """
  Resolves a persistence definition into a normalized struct.
  """
  @spec resolve(nil | t() | storage_tuple() | keyword()) :: {:ok, t() | nil} | {:error, term()}
  def resolve(nil), do: {:ok, nil}
  def resolve(%__MODULE__{} = persistence), do: {:ok, persistence}

  def resolve({adapter, options}) when is_atom(adapter) and is_list(options) do
    if Keyword.keyword?(options) do
      new(adapter: adapter, options: options)
    else
      {:error,
       Jido.Error.validation_error(
         "Persistence storage tuple expects keyword options, got: #{inspect(options)}"
       )}
    end
  end

  def resolve(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      cond do
        storage = Keyword.get(opts, :storage) ->
          resolve(storage)

        adapter = Keyword.get(opts, :adapter) || Keyword.get(opts, :module) ->
          options =
            opts
            |> Keyword.delete(:adapter)
            |> Keyword.delete(:module)
            |> Keyword.delete(:storage)

          new(adapter: adapter, options: options)

        true ->
          {:error,
           Jido.Error.validation_error(
             "Persistence config expects :storage or :adapter, got: #{inspect(opts)}"
           )}
      end
    else
      {:error,
       Jido.Error.validation_error(
         "Persistence config expects a keyword list, got: #{inspect(opts)}"
       )}
    end
  end

  def resolve(other) do
    {:error,
     Jido.Error.validation_error(
       "Persistence config expects nil, a storage tuple, or keyword options, got: #{inspect(other)}"
     )}
  end

  @doc """
  Resolves persistence, raising on error.
  """
  @spec resolve!(nil | t() | storage_tuple() | keyword()) :: t() | nil
  def resolve!(source) do
    case resolve(source) do
      {:ok, persistence} ->
        persistence

      {:error, reason} ->
        raise ArgumentError, "invalid AgentOS persistence config: #{inspect(reason)}"
    end
  end

  @doc """
  Builds a normalized persistence struct.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      adapter = Keyword.get(opts, :adapter)
      options = Keyword.get(opts, :options, [])

      cond do
        not is_atom(adapter) ->
          {:error,
           Jido.Error.validation_error(
             "Persistence adapter must be a module, got: #{inspect(adapter)}"
           )}

        not (is_list(options) and Keyword.keyword?(options)) ->
          {:error,
           Jido.Error.validation_error(
             "Persistence options must be a keyword list, got: #{inspect(options)}"
           )}

        true ->
          {:ok,
           %__MODULE__{
             adapter: adapter,
             options: options,
             storage: {adapter, options}
           }}
      end
    else
      {:error,
       Jido.Error.validation_error(
         "Persistence config expects a keyword list, got: #{inspect(opts)}"
       )}
    end
  end

  @doc """
  Returns the storage tuple for a persistence config.
  """
  @spec storage(t() | nil) :: storage_tuple() | nil
  def storage(nil), do: nil
  def storage(%__MODULE__{storage: storage}), do: storage

  @doc """
  Returns a JSON-friendly summary of persistence config.
  """
  @spec summary(t() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(%__MODULE__{} = persistence) do
    %{
      adapter: inspect(persistence.adapter),
      repo: format_module(Keyword.get(persistence.options, :repo)),
      options: summarize_options(persistence.options)
    }
  end

  defp summarize_options(options) do
    options
    |> Keyword.delete(:repo)
    |> Enum.map(fn {key, value} -> {to_string(key), summarize_value(value)} end)
    |> Map.new()
  end

  defp summarize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp summarize_value(value) when is_binary(value), do: value
  defp summarize_value(value) when is_integer(value), do: value
  defp summarize_value(value) when is_boolean(value), do: value
  defp summarize_value(value), do: inspect(value)

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)
  defp format_module(other), do: summarize_value(other)
end
