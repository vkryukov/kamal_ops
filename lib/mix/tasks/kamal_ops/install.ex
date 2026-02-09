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
            example: :boolean
          ],
          defaults: [
            example: false
          ],
          # KamalOps is intended for local ops tasks, not as a runtime dependency.
          only: [:dev],
          dep_opts: [runtime: false],
          example: "mix igniter.install kamal_ops --example"
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

        if igniter.args.options[:example] do
          add_example_files(igniter)
        else
          igniter
        end
      end

      defp gitignore_has_line?(content, pattern) do
        content
        |> String.split("\n")
        |> Enum.any?(fn line -> String.trim(line) == pattern end)
      end

      defp add_example_files(igniter) do
        app = infer_service_name(igniter)

        deploy_yml = deploy_yml_template(app)
        deploy_prod_yml = deploy_dest_yml_template("prod")

        secrets =
          """
          # Kamal secrets (default destination)
          # https://kamal-deploy.org/docs/configuration/#secrets
          POSTGRES_PASSWORD=
          """
          |> String.trim_leading()

        secrets_common =
          """
          # Kamal secrets (shared, used when `.kamal/secrets.<env>` is missing)
          POSTGRES_PASSWORD=
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

      defp deploy_yml_template(service) do
        """
        # Example Kamal deploy config used by KamalOps mix tasks.
        #
        # Fill in real values based on Kamal's configuration docs:
        # https://kamal-deploy.org/docs/configuration/
        #
        service: #{service}
        primary_role: web

        servers:
          web:
            - 1.2.3.4

        ssh:
          user: deploy

        accessories:
          db:
            image: postgres:16
            host: 1.2.3.4
            port: 5432
            env:
              clear:
                POSTGRES_DB: #{service}_prod
                POSTGRES_USER: #{service}
              secret:
                - POSTGRES_PASSWORD
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
