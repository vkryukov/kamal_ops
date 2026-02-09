defmodule Mix.Tasks.Kamal.Migrate do
  use KamalOps.Task

  @shortdoc "Run migrations in the running release (default or --env)"

  @moduledoc """
  Runs migrations inside the running release container via Kamal.

  ## Usage

      mix kamal.migrate
      mix kamal.migrate --env prod
  """

  @impl Mix.Task
  def run(args) do
    {env, _opts, _rest} = parse_opts!(args)
    root = Project.root!()
    Kamal.app_exec!("bin/migrate", env: env, cd: root)
  end
end
