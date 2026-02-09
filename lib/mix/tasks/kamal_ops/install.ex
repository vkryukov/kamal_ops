case Code.ensure_compiled(Igniter.Mix.Task) do
  {:module, _} ->
    defmodule Mix.Tasks.KamalOps.Install do
      use Igniter.Mix.Task

      @shortdoc "Install kamal_ops into a host project (Igniter)"

      @moduledoc """
      Installs `kamal_ops` conventions into a host project.

      Currently:
      - ensures `.kamal/secrets*` are ignored

      Use via:

          mix igniter.install kamal_ops --example
      """

      @impl Igniter.Mix.Task
      def info(_argv, _composing_task) do
        %Igniter.Mix.Task.Info{
          schema: [
            example: :boolean,
            init: :boolean,
            host: :string
          ],
          defaults: [
            example: false,
            init: false
          ],
          # KamalOps is intended for local ops tasks, not as a runtime dependency.
          only: [:dev],
          dep_opts: [runtime: false],
          example: "mix igniter.install kamal_ops --init --host 1.2.3.4"
        }
      end

      @impl Igniter.Mix.Task
      def igniter(igniter) do
        # Prefer an anchored pattern so we only ignore the repo-root `.kamal` folder.
        patterns = ["/.kamal/secrets*"]
        legacy_patterns = [".kamal/secrets*"]

        igniter =
          Igniter.create_or_update_file(
            igniter,
            ".gitignore",
            Enum.join(patterns, "\n") <> "\n",
            fn source ->
              content = Rewrite.Source.get(source, :content)

              if Enum.any?(patterns ++ legacy_patterns, &gitignore_has_line?(content, &1)) do
                source
              else
                content =
                  content
                  |> String.trim_trailing()
                  |> then(fn c -> if c == "", do: "", else: c <> "\n" end)

                Igniter.update_source(
                  source,
                  igniter,
                  :content,
                  content <> Enum.join(patterns, "\n") <> "\n"
                )
              end
            end
          )

        cond do
          igniter.args.options[:init] ->
            igniter
            |> ensure_kamal_available()
            |> init_project()

          igniter.args.options[:example] ->
            add_example_files(igniter)

          true ->
            igniter
        end
      end

      defp gitignore_has_line?(content, pattern) do
        content
        |> String.split("\n")
        |> Enum.any?(fn line -> String.trim(line) == pattern end)
      end

      defp ensure_kamal_available(igniter) do
        # Don't make unit tests depend on a system binary.
        if igniter.assigns[:test_mode?] do
          igniter
        else
          case System.find_executable("kamal") do
            nil ->
              Igniter.add_issue(
                igniter,
                """
                `--init` requires the `kamal` executable to be installed and available on PATH.

                See: https://kamal-deploy.org/docs/installation/
                """
                |> String.trim()
              )

            _path ->
              igniter
          end
        end
      end

      defp init_project(igniter) do
        service = infer_service_name(igniter)

        {igniter, host} = get_init_host(igniter)

        # If we couldn't get a host, we still return the igniter with issues added.
        if is_binary(host) do
          igniter
          |> add_example_files(service: service, host: host)
          |> Igniter.add_notice("""
          KamalOps init wrote a minimal Kamal config.

          Next steps:
          - Review `config/deploy.yml` (service, image, and servers)
          - Run `kamal setup`
          - Then run `kamal deploy` for subsequent deploys
          """)
        else
          igniter
        end
      end

      defp get_init_host(igniter) do
        host =
          igniter.args.options[:host]
          |> to_string_or_nil()
          |> then(fn v -> if is_binary(v), do: String.trim(v), else: nil end)
          |> case do
            "" -> nil
            v -> v
          end

        cond do
          is_binary(host) ->
            validate_host(igniter, host)

          igniter.args.options[:yes] || !Igniter.Mix.Task.tty?() ->
            {Igniter.add_issue(igniter, "Missing required `--host` for `--init`."), nil}

          true ->
            prompt =
              "Remote server IP/hostname (the value for `servers:` in config/deploy.yml) ❯ "

            case Mix.shell().prompt(prompt) do
              :eof ->
                {Igniter.add_issue(igniter, "No input detected. Provide `--host`."), nil}

              value ->
                value = String.trim(value)

                if value == "" do
                  {Igniter.add_issue(igniter, "Host cannot be blank. Provide `--host`."), nil}
                else
                  validate_host(igniter, value)
                end
            end
        end
      end

      defp validate_host(igniter, host) do
        if host =~ ~r/^\S+$/ do
          {igniter, host}
        else
          {Igniter.add_issue(igniter, "Invalid host: #{inspect(host)} (must not contain spaces)"),
           nil}
        end
      end

      defp to_string_or_nil(nil), do: nil
      defp to_string_or_nil(v) when is_binary(v), do: v
      defp to_string_or_nil(v), do: to_string(v)

      defp add_example_files(igniter) do
        service = infer_service_name(igniter)
        add_example_files(igniter, service: service, host: "1.2.3.4")
      end

      defp add_example_files(igniter, opts) do
        service = Keyword.fetch!(opts, :service)
        host = Keyword.fetch!(opts, :host)

        deploy_yml = deploy_yml_template(service, host)
        deploy_prod_yml = deploy_dest_yml_template("prod")

        secrets =
          """
          # Kamal secrets (default destination).
          #
          # Start with an empty file. Add keys here only if you reference them
          # from `config/deploy*.yml` via e.g. `env.secret`, `registry.password`,
          # or accessory `env.secret`.
          #
          # https://kamal-deploy.org/docs/configuration/#secrets
          """
          |> String.trim_leading()

        secrets_common =
          """
          # Kamal secrets (shared, used when `.kamal/secrets.<env>` is missing)
          """
          |> String.trim_leading()

        igniter
        |> Igniter.mkdir("config")
        |> Igniter.mkdir(".kamal")
        |> Igniter.create_new_file("config/deploy.yml", deploy_yml, on_exists: :skip)
        |> Igniter.create_new_file("config/deploy.prod.yml", deploy_prod_yml, on_exists: :skip)
        |> Igniter.create_new_file(".kamal/secrets", secrets, on_exists: :skip)
        |> Igniter.create_new_file(".kamal/secrets-common", secrets_common, on_exists: :skip)
      end

      defp infer_service_name(igniter) do
        # In real installs, Mix.Project.config() points at the host project.
        # In Igniter.Test mode, it points at this project, so prefer the in-memory files.
        cond do
          igniter.assigns[:test_mode?] &&
            is_map(igniter.assigns[:test_files]) &&
              is_binary(igniter.assigns[:test_files]["mix.exs"]) ->
            parse_app_from_mix_exs(igniter.assigns[:test_files]["mix.exs"])

          is_atom(Mix.Project.config()[:app]) ->
            Mix.Project.config()[:app] |> to_string()

          true ->
            igniter
            |> Igniter.include_existing_file("mix.exs")
            |> Map.get(:rewrite)
            |> Rewrite.source!("mix.exs")
            |> Rewrite.Source.get(:content)
            |> parse_app_from_mix_exs()
        end
      end

      defp parse_app_from_mix_exs(content) when is_binary(content) do
        case Regex.run(~r/\bapp:\s*:(\w+)/, content) do
          [_, app] -> app
          _ -> "app"
        end
      end

      defp deploy_yml_template(service, host) do
        """
        # Minimal Kamal deploy config used by KamalOps mix tasks.
        #
        # Minimum you need to get started is typically:
        #
        # - a server IP (or hostname) you can SSH into
        # - root SSH access (Kamal defaults to `root` if you omit `ssh.user`)
        #
        # From there, you can use Kamal's "local registry" to avoid creating a
        # Docker registry account on day 1:
        #
        #   registry:
        #     server: localhost:5000
        #
        # Fill in real values based on Kamal's configuration docs:
        # https://kamal-deploy.org/docs/configuration/
        #
        service: #{service}
        image: #{service}

        servers:
          - #{host}

        registry:
          server: localhost:5000

        # If you can't SSH as root, set a user:
        #
        # ssh:
        #   user: deploy
        #
        # If you need DB tasks (`mix kamal.db.*`), define a postgres accessory.
        # KamalOps assumes a convention that one accessory is "the DB".
        #
        # accessories:
        #   db:
        #     image: postgres:16
        #     host: #{host}
        #     port: 5432
        #     env:
        #       clear:
        #         POSTGRES_DB: #{service}_prod
        #         POSTGRES_USER: #{service}
        #       secret:
        #         - POSTGRES_PASSWORD
        """
        |> String.trim_leading()
      end

      # Destination file must parse to a map; comment-only YAML parses as nil.
      defp deploy_dest_yml_template(env) do
        """
        # Destination overrides for `#{env}`.
        {}
        """
        |> String.trim_leading()
      end
    end

  {:error, _reason} ->
    defmodule Mix.Tasks.KamalOps.Install do
      use Mix.Task

      @shortdoc "Install kamal_ops into a host project (requires Igniter)"

      @impl Mix.Task
      def run(_args) do
        raise Mix.Error,
              "Igniter is not available. Install Igniter and run via `mix igniter.install kamal_ops`."
      end
    end
end
