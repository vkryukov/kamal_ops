defmodule KamalOps.EnvTest do
  use ExUnit.Case, async: true

  alias KamalOps.Env

  test "deploy_config_paths/2 returns base only for default env" do
    root = make_root!(%{"config/deploy.yml" => "service: x\n"})
    assert Env.deploy_config_paths(nil, root: root) == [Path.join(root, "config/deploy.yml")]
  end

  test "deploy_config_paths/2 returns base + destination for named env" do
    root =
      make_root!(%{
        "config/deploy.yml" => "service: x\n",
        "config/deploy.prod.yml" => "service: x\n"
      })

    assert Env.deploy_config_paths("prod", root: root) == [
             Path.join(root, "config/deploy.yml"),
             Path.join(root, "config/deploy.prod.yml")
           ]
  end

  test "deploy_config_paths/2 raises if destination file missing" do
    root = make_root!(%{"config/deploy.yml" => "service: x\n"})

    assert_raise Mix.Error, ~r/Missing destination deploy config/, fn ->
      Env.deploy_config_paths("prod", root: root)
    end
  end

  test "kamal_secrets_path/2 uses secrets.<env> if present else secrets-common" do
    root =
      make_root!(%{
        ".kamal/secrets-common" => "A=1\n",
        ".kamal/secrets.prod" => "A=2\n"
      })

    assert Env.kamal_secrets_path("prod", root: root) == Path.join(root, ".kamal/secrets.prod")

    root =
      make_root!(%{
        ".kamal/secrets-common" => "A=1\n"
      })

    assert Env.kamal_secrets_path("prod", root: root) == Path.join(root, ".kamal/secrets-common")
  end

  defp make_root!(files) when is_map(files) do
    root =
      Path.join(
        System.tmp_dir!(),
        "kamal_ops_test_#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
      )

    File.mkdir_p!(root)

    Enum.each(files, fn {rel, contents} ->
      path = Path.join(root, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end)

    root
  end
end
