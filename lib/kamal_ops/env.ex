defmodule KamalOps.Env do
  @moduledoc """
  Shared destination selection for Kamal ops tasks.

  Tasks optionally accept `--env NAME`, which maps to Kamal destinations (`kamal -d NAME`).

  - If `--env` is omitted:
    - config: `config/deploy.yml`
    - secrets: `.kamal/secrets`
    - no `kamal -d ...`
  - If `--env NAME` is provided:
    - config: `config/deploy.yml` merged with `config/deploy.NAME.yml` (destination overrides base)
    - secrets: `.kamal/secrets.NAME` if it exists, otherwise `.kamal/secrets-common`
    - pass `kamal -d NAME`
  """

  alias KamalOps.Project

  @type env_name :: nil | String.t()

  @spec parse_env!(String.t() | nil) :: env_name
  def parse_env!(nil), do: nil

  def parse_env!(env) when is_binary(env) do
    env = String.trim(env)

    if env == "" do
      raise ArgumentError, "--env must be a non-empty string"
    end

    if env =~ ~r/^[A-Za-z0-9_-]+$/ do
      env
    else
      raise ArgumentError,
            "--env contains unsupported characters (allowed: letters, numbers, underscore, dash)"
    end
  end

  @spec deploy_config_paths(env_name, keyword()) :: [String.t()]
  def deploy_config_paths(env, opts \\ []) do
    root = Keyword.get(opts, :root, Project.root!())

    base = Path.join(root, "config/deploy.yml")

    if is_nil(env) do
      [base]
    else
      dest = Path.join(root, "config/deploy.#{env}.yml")

      if File.exists?(dest) do
        [base, dest]
      else
        raise Mix.Error, "Missing destination deploy config: #{dest}"
      end
    end
  end

  @spec kamal_dest_args(env_name) :: [String.t()]
  def kamal_dest_args(nil), do: []
  def kamal_dest_args(env) when is_binary(env), do: ["-d", env]

  @spec kamal_secrets_path(env_name, keyword()) :: String.t()
  def kamal_secrets_path(env, opts \\ []) do
    root = Keyword.get(opts, :root, Project.root!())

    if is_nil(env) do
      Path.join(root, ".kamal/secrets")
    else
      dest = Path.join(root, ".kamal/secrets.#{env}")

      if File.exists?(dest) do
        dest
      else
        Path.join(root, ".kamal/secrets-common")
      end
    end
  end
end
