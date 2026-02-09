defmodule Mix.Tasks.Kamal.Seeds do
  use KamalOps.Task, switches: [app: :string]

  @shortdoc "Run seeds in the running release (default or --env)"

  @moduledoc """
  Runs `priv/repo/seeds.exs` inside the running release container via Kamal.

  ## Usage

      mix kamal.seeds
      mix kamal.seeds --env prod
      mix kamal.seeds --env prod --app my_app
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, _rest} = parse_opts!(args)

    root = Project.root!()
    app = KamalOps.App.parse_app!(opts[:app])

    eval =
      "Application.ensure_all_started(:#{app}); " <>
        ~s|Code.eval_file(Path.join(:code.priv_dir(:#{app}), "repo/seeds.exs"))|

    Kamal.app_eval!(eval, env: env, cd: root, app: app)
  end
end
