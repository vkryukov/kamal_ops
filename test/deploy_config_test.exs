defmodule KamalOps.DeployConfigTest do
  use ExUnit.Case, async: true

  alias KamalOps.DeployConfig

  test "load!/1 deep-merges destination over base" do
    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        ssh:
          user: root
        accessories:
          db:
            env:
              clear:
                POSTGRES_DB: base_db
        """,
        "config/deploy.prod.yml" => """
        accessories:
          db:
            env:
              clear:
                POSTGRES_DB: prod_db
        """
      })

    dc =
      DeployConfig.load!([
        Path.join(root, "config/deploy.yml"),
        Path.join(root, "config/deploy.prod.yml")
      ])

    assert DeployConfig.service!(dc) == "app"
    assert DeployConfig.ssh_user(dc) == "root"
    assert DeployConfig.db_name!(dc, "db") == "prod_db"
  end

  test "server_hosts/2 supports servers list and servers web list" do
    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        servers:
          - 1.2.3.4
          - 2.3.4.5
        """
      })

    dc = DeployConfig.load!([Path.join(root, "config/deploy.yml")])
    assert DeployConfig.server_hosts(dc, "web") == ["1.2.3.4", "2.3.4.5"]

    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        servers:
          web:
            - 1.2.3.4
        """
      })

    dc = DeployConfig.load!([Path.join(root, "config/deploy.yml")])
    assert DeployConfig.server_hosts(dc, "web") == ["1.2.3.4"]
  end

  test "accessory_ssh_host!/3 supports explicit host, hosts, and role fallback" do
    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        servers:
          web:
            - 9.9.9.9
        accessories:
          db:
            host: 1.1.1.1
        """
      })

    dc = DeployConfig.load!([Path.join(root, "config/deploy.yml")])
    assert DeployConfig.accessory_ssh_host!(dc, "db") == "1.1.1.1"

    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        servers:
          web:
            - 9.9.9.9
        accessories:
          db:
            hosts: [2.2.2.2, 3.3.3.3]
        """
      })

    dc = DeployConfig.load!([Path.join(root, "config/deploy.yml")])
    assert DeployConfig.accessory_ssh_host!(dc, "db") == "2.2.2.2"

    root =
      make_root!(%{
        "config/deploy.yml" => """
        service: app
        servers:
          web:
            - 9.9.9.9
          worker:
            - 8.8.8.8
        accessories:
          db:
            role: worker
        """
      })

    dc = DeployConfig.load!([Path.join(root, "config/deploy.yml")])
    assert DeployConfig.accessory_ssh_host!(dc, "db") == "8.8.8.8"
  end

  defp make_root!(files) when is_map(files) do
    root = Path.join(System.tmp_dir!(), "kamal_ops_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    Enum.each(files, fn {rel, contents} ->
      path = Path.join(root, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end)

    root
  end
end
