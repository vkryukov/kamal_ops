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
      def igniter(igniter) do
        pattern = ".kamal/secrets*"

        Igniter.create_or_update_file(igniter, ".gitignore", "#{pattern}\n", fn source ->
          content = Rewrite.Source.get(source, :content)

          if gitignore_has_line?(content, pattern) do
            source
          else
            content =
              content
              |> String.trim_trailing()
              |> then(fn c -> if c == "", do: "", else: c <> "\n" end)

            Igniter.update_source(source, igniter, :content, content <> pattern <> "\n")
          end
        end)
      end

      defp gitignore_has_line?(content, pattern) do
        content
        |> String.split("\n")
        |> Enum.any?(fn line -> String.trim(line) == pattern end)
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
