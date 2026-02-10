defmodule Mix.Tasks.Kamal.Db.Tunnel do
  use KamalOps.Task,
    switches: [port: :integer, ssh_opts: :string, db_accessory: :string, role: :string],
    extra_args: ~s|[--db-accessory NAME] [--port 5432] [--ssh-opts "..."] [--role ROLE]|

  alias KamalOps.Cmd

  @shortdoc "Open an SSH tunnel to the Kamal DB accessory (default or --env)"

  @moduledoc """
  Opens an SSH port forward to the remote Postgres container managed by Kamal.

  This is a foreground command; stop it with Ctrl-C.

  You can also pass `--role ROLE` (or set `KAMAL_OPS_ROLE`) to influence which
  server role is used when the accessory doesn't define explicit hosts.

  SSH options can be set via `--ssh-opts` or `SSH_OPTS`, and the ssh binary can
  be overridden with `SSH_COMMAND`.

  ## Usage

      mix kamal.db.tunnel
      mix kamal.db.tunnel --env prod --port 5433
      mix kamal.db.tunnel --env prod --ssh-opts "-i ~/.ssh/id_rsa"
      mix kamal.db.tunnel --env prod --db-accessory db
      mix kamal.db.tunnel --env prod --role worker
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, _rest} = parse_opts!(args)

    local_port = opts[:port] || 5432
    ssh_opts = opts[:ssh_opts] || System.get_env("SSH_OPTS") || ""
    role = opts[:role] || System.get_env("KAMAL_OPS_ROLE")

    root = Project.root!()

    dc = DeployConfig.load!(Env.deploy_config_paths(env, root: root))
    db_accessory = DeployConfig.db_accessory_name!(dc, opts[:db_accessory])

    ssh_host =
      DeployConfig.accessory_ssh_host!(dc, db_accessory, role)

    ssh_user = DeployConfig.ssh_user(dc) || "root"
    db_container_prefix = DeployConfig.accessory_service_name(dc, db_accessory)

    remote_container = remote_db_container!(ssh_user, ssh_host, ssh_opts, db_container_prefix)

    {remote_host, remote_port} =
      remote_db_endpoint!(ssh_user, ssh_host, ssh_opts, remote_container)

    Mix.shell().info("Forwarding #{db_accessory} on #{ssh_host} to localhost:#{local_port}")

    Cmd.exec!(
      ssh_command(),
      ssh_forward_args(ssh_user, ssh_host, ssh_opts, local_port, remote_host, remote_port)
    )
  end

  defp remote_db_container!(ssh_user, ssh_host, ssh_opts, db_container_prefix) do
    container =
      ssh_capture!(
        ssh_user,
        ssh_host,
        ssh_opts,
        "docker ps --format '{{.Names}}' | grep -m 1 -F '#{db_container_prefix}'"
      )

    if container == "" do
      raise Mix.Error,
            "Could not find a running #{db_container_prefix} container on #{ssh_host} (check deploy config/accessories)"
    end

    container
  end

  defp remote_db_endpoint!(ssh_user, ssh_host, ssh_opts, remote_container) do
    published_port = published_port(ssh_user, ssh_host, ssh_opts, remote_container)

    if published_port != "" do
      {"127.0.0.1", published_port}
    else
      ip =
        ssh_capture!(
          ssh_user,
          ssh_host,
          ssh_opts,
          "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' #{remote_container}"
        )

      if ip == "" do
        raise Mix.Error, "Failed to resolve remote DB host for #{remote_container}"
      end

      {ip, "5432"}
    end
  end

  defp published_port(ssh_user, ssh_host, ssh_opts, remote_container) do
    ssh_capture!(
      ssh_user,
      ssh_host,
      ssh_opts,
      "docker port #{remote_container} 5432/tcp 2>/dev/null || true"
    )
    |> String.split("\n", trim: true)
    |> List.first()
    |> parse_published_port()
  end

  defp parse_published_port(nil), do: ""

  defp parse_published_port(line) do
    case Regex.run(~r/:(\d+)\s*$/, line) do
      [_, port] -> port
      _ -> ""
    end
  end

  defp ssh_forward_args(ssh_user, ssh_host, ssh_opts, local_port, remote_host, remote_port) do
    ["-o", "ExitOnForwardFailure=yes"] ++
      split_ssh_opts(ssh_opts) ++
      ["-L", "#{local_port}:#{remote_host}:#{remote_port}", "#{ssh_user}@#{ssh_host}", "-N"]
  end

  defp ssh_command, do: System.get_env("SSH_COMMAND") || "ssh"

  defp ssh_capture!(ssh_user, ssh_host, ssh_opts, remote_cmd) do
    {out, status} =
      System.cmd(
        ssh_command(),
        split_ssh_opts(ssh_opts) ++ ["#{ssh_user}@#{ssh_host}", remote_cmd],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise Mix.Error, "ssh failed (#{status}): #{String.trim(out)}"
    end

    String.trim(out)
  end

  defp split_ssh_opts(""), do: []

  defp split_ssh_opts(opts) do
    OptionParser.split(opts)
  end
end
