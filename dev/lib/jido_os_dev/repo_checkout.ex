defmodule JidoOSDev.RepoCheckout do
  @moduledoc """
  Thin adapter around a local Git checkout for the dev host.

  This module is intentionally outside `Jido.AgentOS` itself because it is not
  kernel behavior. It is host-app glue that answers repo-specific questions for
  `JidoOSDev.RepoWorkspace` by using `git_cli` plus guarded reads from the
  working tree.
  """

  alias Git.Error, as: GitError

  @max_read_chars 12_000

  @spec inspect_checkout(String.t()) :: {:ok, map()} | {:error, term()}
  def inspect_checkout(path) do
    with {:ok, repo_path} <- normalize_checkout(path),
         {:ok, branch} <- git(repo_path, :branch, ["--show-current"]),
         {:ok, head} <- git(repo_path, :rev_parse, ["--short", "HEAD"]),
         {:ok, status} <- git(repo_path, :status, ["--porcelain"]),
         {:ok, tracked_files} <- git(repo_path, :ls_files) do
      changed_files = parse_status(status)
      tracked = parse_lines(tracked_files)

      {:ok,
       %{
         path: repo_path,
         repo_name: Path.basename(repo_path),
         branch: blank_to_value(branch, "detached"),
         head: String.trim(head),
         dirty: changed_files != [],
         changed_files: changed_files,
         file_count: length(tracked),
         changed_count: length(changed_files),
         tracked_files: tracked,
         scanned_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  @spec tracked_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def tracked_files(path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)

    with {:ok, repo_path} <- normalize_checkout(path),
         {:ok, files} <- git(repo_path, :ls_files) do
      {:ok, files |> parse_lines() |> Enum.take(limit)}
    end
  end

  @spec read_file(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def read_file(path, relative_path, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, @max_read_chars)

    with {:ok, repo_path} <- normalize_checkout(path),
         {:ok, resolved_path} <- resolve_repo_path(repo_path, relative_path),
         {:ok, contents} <- File.read(resolved_path) do
      trimmed =
        if String.length(contents) > max_chars do
          String.slice(contents, 0, max_chars)
        else
          contents
        end

      {:ok,
       %{
         path: Path.relative_to(resolved_path, repo_path),
         content: trimmed,
         truncated: String.length(contents) > String.length(trimmed)
       }}
    else
      {:error, :enoent} ->
        {:error, :file_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec default_pod_id(String.t()) :: String.t()
  def default_pod_id(path) do
    path
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
    |> String.downcase()
  end

  defp normalize_checkout(path) do
    expanded = path |> to_string() |> String.trim() |> Path.expand()

    cond do
      expanded == "" ->
        {:error, :missing_repo_path}

      not File.dir?(expanded) ->
        {:error, :repo_not_found}

      true ->
        case git(expanded, :rev_parse, ["--show-toplevel"]) do
          {:ok, top_level} -> {:ok, String.trim(top_level)}
          {:error, _reason} -> {:error, :not_a_git_checkout}
        end
    end
  end

  defp resolve_repo_path(repo_path, relative_path) do
    candidate =
      repo_path
      |> Path.join(relative_path)
      |> Path.expand()

    if String.starts_with?(candidate, repo_path <> "/") or candidate == repo_path do
      {:ok, candidate}
    else
      {:error, :path_outside_repo}
    end
  end

  defp git(path, command, args \\ []) do
    repo = Git.new(path)

    try do
      case apply(Git, command, [repo, args]) do
        {:ok, output} -> {:ok, output}
        {:error, %GitError{message: message}} -> {:error, String.trim(message)}
        {:error, reason} -> {:error, inspect(reason)}
      end
    rescue
      error in ErlangError -> {:error, Exception.message(error)}
    end
  end

  defp parse_status(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      line
      |> String.slice(3..-1//1)
      |> to_string()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_lines(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp blank_to_value(value, fallback) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end
end
