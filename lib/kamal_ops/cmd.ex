defmodule KamalOps.Cmd do
  @moduledoc false

  @type opt ::
          {:cd, String.t()}
          | {:env, [{String.t(), String.t()}]}
          | {:interactive, boolean()}

  @doc """
  Runs an external command and streams its output to the terminal.

  Options:

    * `:cd`          — working directory
    * `:env`         — list of `{key, value}` env vars
    * `:interactive`  — when `true`, the child inherits the terminal directly
      (fd 0/1/2) so that TTY features like Tab completion work end-to-end.
      When `false` (default), stdout/stderr are captured via pipes and
      streamed to `IO.write/1`.
  """
  @spec exec!(String.t(), [String.t()], [opt]) :: :ok
  def exec!(exe, args, opts \\ []) when is_binary(exe) and is_list(args) do
    interactive? = Keyword.get(opts, :interactive, false)

    exe_path =
      System.find_executable(exe) ||
        raise Mix.Error, "Missing executable: #{exe}"

    port_opts =
      if interactive? do
        # :nouse_stdio lets the child inherit the real terminal (fd 0/1/2)
        # so interactive programs (IEx remote, psql) get a proper TTY with
        # features like Tab completion. The port only delivers :exit_status.
        [:nouse_stdio, :exit_status, args: args]
      else
        [:binary, :exit_status, :use_stdio, :stderr_to_stdout, args: args]
      end

    port_opts =
      port_opts
      |> maybe_put_cd(opts)
      |> maybe_put_env(opts)

    port = Port.open({:spawn_executable, exe_path}, port_opts)

    if interactive? do
      await_exit_interactive!(port, exe)
    else
      await_exit!(port, exe)
    end
  end

  defp maybe_put_cd(port_opts, opts) do
    case Keyword.get(opts, :cd) do
      nil -> port_opts
      dir -> Keyword.put(port_opts, :cd, to_charlist(dir))
    end
  end

  defp maybe_put_env(port_opts, opts) do
    case Keyword.get(opts, :env) do
      nil ->
        port_opts

      env when is_list(env) ->
        env =
          Enum.map(env, fn
            {k, v} when is_binary(k) and is_binary(v) -> {to_charlist(k), to_charlist(v)}
          end)

        Keyword.put(port_opts, :env, env)
    end
  end

  # Interactive mode — child owns the terminal, we only wait for exit.
  defp await_exit_interactive!(port, exe) do
    receive do
      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        raise Mix.Error, "Command failed (exit #{status}): #{exe}"
    end
  end

  # Captured mode — stream child stdout/stderr to our terminal.
  defp await_exit!(port, exe) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        await_exit!(port, exe)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        raise Mix.Error, "Command failed (exit #{status}): #{exe}"
    end
  end
end
