defmodule Mix.Tasks.Kamal.Remote do
  use KamalOps.Task, switches: [app: :string]

  @shortdoc "Open a remote IEx shell in the running release (default or --env)"

  @moduledoc """
  Opens a remote IEx shell in the running release container via Kamal.

  ## Usage

      mix kamal.remote
      mix kamal.remote --env prod
      mix kamal.remote --env prod --app my_app
  """

  @impl Mix.Task
  def run(args) do
    {env, opts, _rest} = parse_opts!(args)

    app = KamalOps.App.parse_app!(opts[:app])
    root = Project.root!()

    Kamal.app_exec!("bin/#{app} remote", env: env, interactive: true, cd: root, app: app)
  end
end
