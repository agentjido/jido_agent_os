defmodule JidoOSDev.RepoWorkspace.Prompts do
  @moduledoc false

  alias JidoOSDev.RepoWorkspace.Summary

  @spec specialist_prompt(atom(), map(), map()) :: String.t()
  def specialist_prompt(:planner, repo, task) do
    """
    Build an implementation plan for this repo task.

    Repository: #{repo.repo_name}
    Branch: #{repo.branch}
    Dirty checkout: #{repo.dirty}
    Recently changed files: #{Enum.join(repo.changed_files, ", ") |> Summary.blank("none")}

    Task title: #{task.title}
    Goal: #{task.goal}

    Produce:
    1. Scope summary
    2. Files to inspect
    3. Proposed edits
    4. Tests or checks
    """
  end

  def specialist_prompt(:coder, repo, task) do
    """
    Draft a concrete implementation sketch for this repo task.

    Repository: #{repo.repo_name}
    Branch: #{repo.branch}
    Dirty checkout: #{repo.dirty}

    Task title: #{task.title}
    Goal: #{task.goal}
    Existing plan: #{Summary.blank(task.plan, "No plan stored yet.")}

    Produce a practical patch plan or pseudo-diff. Do not claim the code has already been changed.
    """
  end

  def specialist_prompt(:reviewer, repo, task) do
    """
    Review the proposed coding work for this repo task.

    Repository: #{repo.repo_name}
    Branch: #{repo.branch}
    Dirty checkout: #{repo.dirty}

    Task title: #{task.title}
    Goal: #{task.goal}
    Existing plan: #{Summary.blank(task.plan, "No plan stored yet.")}
    Existing draft: #{Summary.blank(task.draft, "No draft stored yet.")}

    Critique correctness, risks, missing tests, and sharp edges.
    """
  end

  @spec assistant_prompt(map(), map() | nil, String.t()) :: String.t()
  def assistant_prompt(repo, task, prompt) do
    """
    Answer a short repo question for the interactive pod UI.

    Repository: #{repo.repo_name}
    Branch: #{repo.branch}
    Dirty checkout: #{repo.dirty}
    Changed files: #{Enum.join(repo.changed_files, ", ") |> Summary.blank("none")}
    Active task: #{Summary.active_task_summary(task)}

    User question: #{prompt}

    Keep the answer brief and practical. Use repo tools when needed.
    """
  end
end
