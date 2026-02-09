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
    {env, opts, rest} = parse_opts!(args, allow_rest: true)

    app = KamalOps.App.parse_app!(opts[:app])
    root = Project.root!()

    cmd =
      case rest do
        [] -> "bin/#{app} remote"
        extra -> Enum.join(["bin/#{app}", "remote" | extra], " ")
      end

    Kamal.app_exec!(cmd, env: env, interactive: true, cd: root, app: app)
  end
end
