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
            host: :string,
            db: :boolean,
            no_db: :boolean
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
          db? = db_accessory_enabled?(igniter)

          igniter
          |> add_example_files(service: service, host: host, db?: db?)
          |> Igniter.add_notice("""
          KamalOps init wrote a minimal Kamal config.

          Next steps:
          - Review `config/deploy.yml` (service, image, and servers)
          - Run `kamal setup`
          - If you enabled a DB accessory: `kamal accessory boot db`
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
        add_example_files(igniter, service: service, host: "1.2.3.4", db?: false)
      end

      defp add_example_files(igniter, opts) do
        service = Keyword.fetch!(opts, :service)
        host = Keyword.fetch!(opts, :host)
        db? = Keyword.get(opts, :db?, false)

        deploy_yml = deploy_yml_template(service, host, db?: db?)
        deploy_prod_yml = deploy_dest_yml_template("prod")

        secrets_header =
          """
          # Kamal secrets (default destination).
          #
          # Keys here are only used if referenced from `config/deploy*.yml` via
          # e.g. `env.secret`, `registry.password`, or accessory `env.secret`.
          #
          # https://kamal-deploy.org/docs/configuration/#secrets
          """
          |> String.trim_leading()

        secrets_common =
          """
          # Kamal secrets (shared, used when `.kamal/secrets.<env>` is missing)
          """
          |> String.trim_leading()

        igniter =
          igniter
          |> Igniter.mkdir("config")
          |> Igniter.mkdir(".kamal")
          |> Igniter.create_new_file("config/deploy.yml", deploy_yml, on_exists: :skip)
          |> Igniter.create_new_file("config/deploy.prod.yml", deploy_prod_yml, on_exists: :skip)
          |> Igniter.create_or_update_file(".kamal/secrets", secrets_header, fn source ->
            content = Rewrite.Source.get(source, :content)
            content = if String.trim(content) == "", do: secrets_header, else: content
            Igniter.update_source(source, igniter, :content, content)
          end)
          |> Igniter.create_new_file(".kamal/secrets-common", secrets_common, on_exists: :skip)

        if db? do
          add_db_secrets(igniter, service)
        else
          igniter
        end
      end

      defp db_accessory_enabled?(igniter) do
        opts = igniter.args.options

        cond do
          opts[:no_db] ->
            false

          opts[:db] ->
            true

          postgres_detected?(igniter) ->
            true

          true ->
            false
        end
      end

      defp postgres_detected?(igniter) do
        content = host_mix_exs_content(igniter) || ""

        # Keep this heuristic intentionally loose: if we see any of these,
        # the project is almost certainly using Postgres.
        String.contains?(content, "{:postgrex") or
          String.contains?(content, "{:ecto_sql") or
          String.contains?(content, "{:ash_postgres") or
          String.contains?(content, "Ecto.Adapters.Postgres")
      end

      defp host_mix_exs_content(igniter) do
        cond do
          igniter.assigns[:test_mode?] &&
            is_map(igniter.assigns[:test_files]) &&
              is_binary(igniter.assigns[:test_files]["mix.exs"]) ->
            igniter.assigns[:test_files]["mix.exs"]

          true ->
            try do
              igniter
              |> Igniter.include_existing_file("mix.exs")
              |> Map.get(:rewrite)
              |> Rewrite.source!("mix.exs")
              |> Rewrite.Source.get(:content)
            rescue
              _ ->
                nil
            end
        end
      end

      defp add_db_secrets(igniter, service) do
        db_user = service
        db_name = "#{service}_prod"

        # By default accessories use a service name of `<service>-<accessory>`.
        # With accessory name `db`, the hostname is `<service>-db` on the `kamal` network.
        db_host = "#{service}-db"

        password = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        database_url = "ecto://#{db_user}:#{password}@#{db_host}:5432/#{db_name}"

        igniter
        |> ensure_secret_kv(".kamal/secrets", "POSTGRES_PASSWORD", password)
        |> ensure_secret_kv(".kamal/secrets", "DATABASE_URL", database_url)
      end

      defp ensure_secret_kv(igniter, path, key, value) do
        Igniter.create_or_update_file(igniter, path, "#{key}=#{value}\n", fn source ->
          content = Rewrite.Source.get(source, :content)

          if dotenv_has_key?(content, key) do
            source
          else
            content =
              content
              |> String.trim_trailing()
              |> then(fn c -> if c == "", do: "", else: c <> "\n" end)

            Igniter.update_source(source, igniter, :content, content <> "#{key}=#{value}\n")
          end
        end)
      end

      defp dotenv_has_key?(content, key) do
        content
        |> String.split("\n")
        |> Enum.any?(fn line ->
          line = String.trim(line)

          line != "" and not String.starts_with?(line, "#") and
            String.starts_with?(line, key <> "=")
        end)
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

      defp deploy_yml_template(service, host, opts) do
        db? = Keyword.get(opts, :db?, false)
        db_block = if db?, do: deploy_yml_db_block(service, host), else: ""
        env_block = if db?, do: deploy_yml_env_block(), else: ""

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

        #{String.trim_trailing(env_block)}

        # If you can't SSH as root, set a user:
        #
        # ssh:
        #   user: deploy
        #
        #{String.trim_trailing(db_block)}
        """
        |> String.trim_leading()
      end

      defp deploy_yml_env_block do
        """
        env:
          secret:
            - DATABASE_URL
        """
      end

      defp deploy_yml_db_block(service, host) do
        """
        accessories:
          db:
            image: postgres:16
            host: #{host}
            env:
              clear:
                POSTGRES_DB: #{service}_prod
                POSTGRES_USER: #{service}
              secret:
                - POSTGRES_PASSWORD
            directories:
              - #{service}-postgres:/var/lib/postgresql/data
        """
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
