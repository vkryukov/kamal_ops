defmodule Mix.Tasks.Kamal.Db.Url do
  use KamalOps.Task,
    switches: [
      port: :integer,
      print_url: :boolean,
      with_password: :boolean,
      db_accessory: :string
    ],
    extra_args: "[--port 5432] [--print-url] [--with-password]"

  @shortdoc "Print a local DATABASE_URL for a tunneled Kamal DB (default or --env)"

  @moduledoc """
  Prints a `postgres://...` URL for connecting to a Kamal-managed DB via an SSH
  tunnel on localhost.

  This task does not open the tunnel; use `mix kamal.db.tunnel` in another terminal.

  By default, the password is *not* embedded. Use `--with-password` to print a URL
  containing the secret (warning: this prints a secret to your terminal).

  ## Usage

      mix kamal.db.url
      mix kamal.db.url --env prod --port 5433
      mix kamal.db.url --env prod --port 5433 --with-password
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, _rest} = parse_opts!(args)

    port = opts[:port] || 5432
    print_url? = opts[:print_url] || false
    with_password? = opts[:with_password] || false

    root = Project.root!()
    dc = DeployConfig.load!(Env.deploy_config_paths(env, root: root))

    db_accessory = DeployConfig.db_accessory_name!(dc, opts[:db_accessory])
    db_user = DeployConfig.db_user!(dc, db_accessory)
    db_name = DeployConfig.db_name!(dc, db_accessory)

    password =
      if with_password? do
        Mix.shell().error(
          "WARNING: printing a DATABASE_URL containing a secret (POSTGRES_PASSWORD)"
        )

        secrets = Secrets.load_file!(Env.kamal_secrets_path(env, root: root))
        Secrets.get!(secrets, "POSTGRES_PASSWORD")
      else
        Mix.shell().error(
          "NOTE: password not embedded. Set POSTGRES_PASSWORD in your shell, or pass --with-password."
        )

        "${POSTGRES_PASSWORD}"
      end

    url = "postgres://#{db_user}:#{password}@127.0.0.1:#{port}/#{db_name}"

    if print_url? do
      Mix.shell().info(url)
    else
      Mix.shell().info("DATABASE_URL=#{url}")
    end
  end
end
