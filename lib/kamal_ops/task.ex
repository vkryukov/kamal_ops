defmodule KamalOps.Task do
  @moduledoc """
  Shared plumbing for `mix kamal.*` tasks.

  ## Usage

      use KamalOps.Task
      use KamalOps.Task,
        switches: [port: :integer],
        extra_args: "[--port 5432]"

  The usage line defaults to `"mix <task.name> [--env NAME]"`.
  Pass `:extra_args` to append additional arguments to the usage line.
  """

  defmacro __using__(opts) do
    extra_switches = opts[:switches] || []
    extra_args = opts[:extra_args]

    quote do
      use Mix.Task

      alias KamalOps.App
      alias KamalOps.DeployConfig
      alias KamalOps.Env
      alias KamalOps.Kamal
      alias KamalOps.Project
      alias KamalOps.Secrets

      @switches Keyword.merge([env: :string], unquote(extra_switches))

      @_task_usage [
                     __MODULE__
                     |> Module.split()
                     |> Enum.drop(2)
                     |> Enum.map_join(".", &Macro.underscore/1)
                     |> then(&"mix #{&1} [--env NAME]"),
                     unquote(extra_args)
                   ]
                   |> Enum.reject(&is_nil/1)
                   |> Enum.join(" ")

      defp parse_opts!(args, parse_opts \\ []) do
        {opts, rest, invalid} = OptionParser.parse(args, switches: @switches)

        if invalid != [] do
          usage!("Invalid options: #{inspect(invalid)}")
        end

        if rest != [] and not Keyword.get(parse_opts, :allow_rest, false) do
          usage!("Unexpected arguments: #{inspect(rest)}")
        end

        env = Env.parse_env!(opts[:env])
        {env, opts, rest}
      end

      defp usage!(msg) do
        Mix.shell().error("""
        #{msg}

        Usage:
          #{@_task_usage}
        """)

        raise Mix.Error, msg
      end
    end
  end
end
