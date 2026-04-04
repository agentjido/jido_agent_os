defmodule JidoOSDev.RepoCheckoutTest do
  use ExUnit.Case, async: true

  alias JidoOSDev.RepoCheckout

  test "inspect_checkout preserves changed file paths from git status" do
    repo_dir = Path.join(System.tmp_dir!(), "repo-checkout-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo_dir)

    on_exit(fn -> File.rm_rf(repo_dir) end)

    assert {"Initialized empty Git repository in " <> _rest, 0} =
             System.cmd("git", ["init"], cd: repo_dir, stderr_to_stdout: true)

    assert {"", 0} = System.cmd("git", ["config", "user.name", "Jido Test"], cd: repo_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "jido@example.com"], cd: repo_dir)

    file_path = Path.join(repo_dir, "alpha.txt")
    File.write!(file_path, "one\n")

    assert {"", 0} = System.cmd("git", ["add", "alpha.txt"], cd: repo_dir)

    assert {_, 0} =
             System.cmd("git", ["commit", "-m", "init"], cd: repo_dir, stderr_to_stdout: true)

    File.write!(file_path, "two\n")

    assert {:ok, checkout} = RepoCheckout.inspect_checkout(repo_dir)
    assert checkout.changed_files == ["alpha.txt"]
  end
end
