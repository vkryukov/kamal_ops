defmodule KamalOps.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  defp file_content!(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  test "installer ensures Kamal secrets are ignored" do
    igniter =
      test_project()
      |> Igniter.compose_task("kamal_ops.install", [])

    content = file_content!(igniter, ".gitignore")
    assert String.contains?(content, "/.kamal/secrets*")
  end

  test "installer is idempotent for .gitignore" do
    igniter =
      test_project()
      |> Igniter.compose_task("kamal_ops.install", [])
      |> Igniter.compose_task("kamal_ops.install", [])

    content = file_content!(igniter, ".gitignore")
    assert length(String.split(content, "/.kamal/secrets*", trim: true)) == 2
  end

  test "installer --example scaffolds deploy config and secrets" do
    igniter =
      test_project(app_name: :image_dojo)
      |> Igniter.compose_task("kamal_ops.install", ["--example"])
      |> assert_creates("config/deploy.yml")
      |> assert_creates("config/deploy.prod.yml")
      |> assert_creates(".kamal/secrets")
      |> assert_creates(".kamal/secrets-common")

    assert file_content!(igniter, "config/deploy.yml") =~ "service: image_dojo\n"
    assert file_content!(igniter, "config/deploy.prod.yml") =~ "{}\n"
    assert file_content!(igniter, ".kamal/secrets") =~ "POSTGRES_PASSWORD=\n"
    assert file_content!(igniter, ".kamal/secrets-common") =~ "POSTGRES_PASSWORD=\n"
  end
end
