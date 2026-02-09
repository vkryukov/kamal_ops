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
    assert file_content!(igniter, "config/deploy.yml") =~ "registry:\n  server: localhost:5000\n"
    assert file_content!(igniter, "config/deploy.prod.yml") =~ "{}\n"
    assert file_content!(igniter, ".kamal/secrets") =~ "# Kamal secrets"
  end

  test "installer --init --host scaffolds deploy config with provided host" do
    igniter =
      test_project(app_name: :image_dojo)
      |> Igniter.compose_task("kamal_ops.install", ["--init", "--host", "9.9.9.9"])
      |> assert_creates("config/deploy.yml")

    assert file_content!(igniter, "config/deploy.yml") =~ "servers:\n  - 9.9.9.9\n"
  end

  test "installer --init auto-adds Postgres accessory when deps indicate Postgres" do
    mix_exs = """
    defmodule ImageDojo.MixProject do
      use Mix.Project

      def project do
        [app: :image_dojo, version: "0.1.0", deps: deps()]
      end

      defp deps do
        [
          {:ecto_sql, \"~> 3.13\"},
          {:postgrex, \">= 0.0.0\"}
        ]
      end
    end
    """

    igniter =
      test_project(
        app_name: :image_dojo,
        files: %{"mix.exs" => mix_exs}
      )
      |> Igniter.compose_task("kamal_ops.install", ["--init", "--host", "9.9.9.9"])
      |> assert_creates("config/deploy.yml")

    deploy = file_content!(igniter, "config/deploy.yml")
    assert deploy =~ "accessories:\n  db:\n"
    assert deploy =~ "image: postgres:16\n"
    assert deploy =~ "host: 9.9.9.9\n"
    assert deploy =~ "POSTGRES_DB: image_dojo_prod\n"

    secrets = file_content!(igniter, ".kamal/secrets")
    assert secrets =~ ~r/POSTGRES_PASSWORD=\S+/
    assert secrets =~ ~r|DATABASE_URL=ecto://image_dojo:\S+@image_dojo-db:5432/image_dojo_prod|
  end
end
