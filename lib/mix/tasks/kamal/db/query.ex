defmodule Mix.Tasks.Kamal.Db.Query do
  use KamalOps.Task, switches: [db_accessory: :string], extra_args: ~s|"select 1"|

  @shortdoc "Run a SQL query inside the Kamal DB accessory (default or --env)"

  @moduledoc """
  Runs a SQL query via `psql` inside the running Kamal DB accessory.

  Output is unaligned / tuples-only (`-X -A -t`) and stops on error.

  ## Usage

      mix kamal.db.query "select count(*) from images;"
      mix kamal.db.query --env prod "select count(*) from images;"
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, rest} = parse_opts!(args, allow_rest: true)

    sql =
      case rest do
        [] -> usage!("Missing SQL string")
        parts -> Enum.join(parts, " ")
      end

    root = Project.root!()
    dc = DeployConfig.load!(Env.deploy_config_paths(env, root: root))
    db_accessory = DeployConfig.db_accessory_name!(dc, opts[:db_accessory])
    db_host = DeployConfig.accessory_service_name(dc, db_accessory)
    db_user = DeployConfig.db_user!(dc, db_accessory)
    db_name = DeployConfig.db_name!(dc, db_accessory)

    secrets = Secrets.load_file!(Env.kamal_secrets_path(env, root: root))
    password = Secrets.get!(secrets, "POSTGRES_PASSWORD")

    script = ~s"""
    set -eu
    tmp="$(mktemp /tmp/kamal_ops_psql_query_XXXXXX.sql)"
    cleanup() { rm -f "$tmp"; }
    trap cleanup EXIT
    printf "%s" "$2" | base64 -d > "$tmp"
    PGPASSWORD="$(printf "%s" "$1" | base64 -d)" psql --host=#{db_host} -U #{db_user} -d #{db_name} -v ON_ERROR_STOP=1 -X -A -t -f "$tmp"
    """

    Kamal.accessory_sh!(db_accessory, script, [password, sql],
      env: env,
      quiet: true,
      cd: root
    )
  end
end
