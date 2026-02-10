defmodule KamalOps.Kamal do
  @moduledoc """
  Runs commands inside Kamal-managed containers.

  All remote commands are passed as a single positional string to avoid quoting
  breakage across the `kamal -> ssh -> docker -> sh` layers, and to sidestep
  Kamal's `-c/--config-file` flag conflict.
  """

  alias KamalOps.App
  alias KamalOps.Cmd
  alias KamalOps.Env

  @doc """
  Run a command string in the app container via `kamal app exec`.

  The command is passed after `--` so Kamal's option parser never sees flags
  that belong to the remote command.

  ## Options

    * `:env`          — Kamal destination name (`nil` for default)
    * `:interactive`  — pass `--interactive` to Kamal and give the child direct
      terminal access locally (default `false`)
    * `:reuse`        — pass `--reuse` (default `true`)
    * `:primary`      — pass `--primary` (default `true`)
    * `:cd`           — working directory for the local kamal process
  """
  @spec app_exec!(String.t(), keyword()) :: :ok
  def app_exec!(cmd, opts \\ []) when is_binary(cmd) do
    env = Keyword.get(opts, :env)
    interactive? = Keyword.get(opts, :interactive, false)
    reuse? = Keyword.get(opts, :reuse, true)
    # Default to primary for consistency (e.g. remote IEx should attach to primary).
    primary? = Keyword.get(opts, :primary, true)

    kamal_args =
      ["app", "exec"] ++
        Env.kamal_dest_args(env) ++
        bool_flag(interactive?, "--interactive") ++
        bool_flag(reuse?, "--reuse") ++
        bool_flag(primary?, "--primary") ++
        ["--", cmd]

    Cmd.exec!("kamal", kamal_args, cmd_opts(opts))
  end

  @doc """
  Evaluate an Elixir expression in the running release using `bin/<app> eval '…'`.

  Raises if the expression contains single quotes (they break the wrapper).
  """
  @spec app_eval!(String.t(), keyword()) :: :ok
  def app_eval!(code, opts \\ []) when is_binary(code) do
    if String.contains?(code, "'") do
      raise ArgumentError,
            "eval code must not contain single quotes (use double quotes for Elixir strings)"
    end

    app = App.parse_app!(Keyword.get(opts, :app))
    app_exec!("bin/#{app} eval '#{code}'", Keyword.put(opts, :app, app))
  end

  @doc """
  Run a command string in a Kamal accessory container via `kamal accessory exec`.
  """
  @spec accessory_exec!(String.t(), String.t(), keyword()) :: :ok
  def accessory_exec!(accessory, cmd, opts \\ [])
      when is_binary(accessory) and is_binary(cmd) do
    env = Keyword.get(opts, :env)
    interactive? = Keyword.get(opts, :interactive, false)
    quiet? = Keyword.get(opts, :quiet, false)

    kamal_args =
      ["accessory", "exec"] ++
        Env.kamal_dest_args(env) ++
        [accessory] ++
        bool_flag(interactive?, "--interactive") ++
        bool_flag(quiet?, "--quiet") ++
        [cmd]

    Cmd.exec!("kamal", kamal_args, cmd_opts(opts))
  end

  @doc """
  Run a shell script in a Kamal accessory container with base64-encoded args.

  The script is wrapped in `sh -c '<script>' _ <b64_arg1> <b64_arg2> …` so
  positional parameters arrive intact through intermediate shells.
  """
  @spec accessory_sh!(String.t(), String.t(), [String.t()], keyword()) :: :ok
  def accessory_sh!(accessory, script, args \\ [], opts \\ [])
      when is_binary(accessory) and is_binary(script) and is_list(args) do
    if String.contains?(script, "'") do
      raise ArgumentError,
            "shell script must not contain single quotes (use double quotes inside the script)"
    end

    b64_args = Enum.map(args, &Base.encode64/1)
    cmd = Enum.join(["sh -c '#{String.trim(script)}' _" | b64_args], " ")
    accessory_exec!(accessory, cmd, opts)
  end

  defp bool_flag(true, flag), do: [flag]
  defp bool_flag(false, _flag), do: []

  defp cmd_opts(opts) do
    opts
    |> Keyword.take([:cd, :interactive])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
