defmodule Mix.Tasks.Kamal.Secrets.Check do
  use KamalOps.Task

  @shortdoc "Validate that deploy secrets are present (no values printed)"

  @moduledoc """
  Checks that the required secret keys referenced from `config/deploy*.yml`
  exist in the appropriate Kamal secrets file.

  Secrets file selection follows Kamal destinations:

  - default: `.kamal/secrets`
  - named env: `.kamal/secrets.<env>` if present, otherwise `.kamal/secrets-common`

  ## Usage

      mix kamal.secrets.check
      mix kamal.secrets.check --env prod
  """

  @impl Mix.Task
  def run(args) do
    {env, _opts, _rest} = parse_opts!(args)

    root = Project.root!()
    secrets_path = Env.kamal_secrets_path(env, root: root)

    required_keys = required_keys(env, root)
    secrets = Secrets.load_file!(secrets_path)
    missing = missing_keys(required_keys, secrets)

    report!(missing, required_keys, secrets_path)
  end

  defp required_keys(env, root) do
    dc = DeployConfig.load!(Env.deploy_config_paths(env, root: root))
    DeployConfig.secret_keys(dc)
  end

  defp missing_keys(required_keys, secrets) do
    required_keys
    |> Enum.uniq()
    |> Enum.filter(fn key -> is_nil(Secrets.get(secrets, key)) end)
  end

  defp report!(missing, required_keys, secrets_path) do
    case missing do
      [] ->
        Mix.shell().info(
          "OK: all #{length(required_keys)} required keys are present in #{secrets_path}"
        )

      keys ->
        Mix.shell().error("Missing #{length(keys)} keys in #{secrets_path}:")
        Enum.each(keys, &Mix.shell().error("  - #{&1}"))
        raise Mix.Error, "missing secrets"
    end
  end
end
