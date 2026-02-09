defmodule Mix.Tasks.Kamal.Db.Psql do
  use KamalOps.Task, switches: [db_accessory: :string]

  @shortdoc "Open psql inside the Kamal DB accessory (default or --env)"

  @moduledoc """
  Opens an interactive `psql` shell inside the running Kamal DB accessory.

  ## Usage

      mix kamal.db.psql
      mix kamal.db.psql --env prod
      mix kamal.db.psql --env prod --db-accessory db
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, _rest} = parse_opts!(args)

    root = Project.root!()

    dc = DeployConfig.load!(Env.deploy_config_paths(env, root: root))
    db_accessory = DeployConfig.db_accessory_name!(dc, opts[:db_accessory])
    db_host = DeployConfig.accessory_service_name(dc, db_accessory)
    db_user = DeployConfig.db_user!(dc, db_accessory)
    db_name = DeployConfig.db_name!(dc, db_accessory)

    secrets = Secrets.load_file!(Env.kamal_secrets_path(env, root: root))
    password = Secrets.get!(secrets, "POSTGRES_PASSWORD")

    script =
      ~s[PGPASSWORD="$(printf "%s" "$1" | base64 -d)" psql --host=#{db_host} -U #{db_user} -d #{db_name}]

    Kamal.accessory_sh!(db_accessory, script, [password],
      env: env,
      interactive: true,
      cd: root
    )
  end
end
