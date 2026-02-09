# KamalOps

Reusable helpers and `mix kamal.*` Mix tasks for operating [Kamal](https://kamal-deploy.org/)
deployments from Elixir projects.

## Tasks

- `mix kamal.remote [--env NAME] [--app APP]`
- `mix kamal.migrate [--env NAME]`
- `mix kamal.seeds [--env NAME] [--app APP]`
- `mix kamal.secrets.check [--env NAME]`
- `mix kamal.db.psql [--env NAME] [--db-accessory NAME]`
- `mix kamal.db.query [--env NAME] [--db-accessory NAME] "SQL..."`
- `mix kamal.db.tunnel [--env NAME] [--db-accessory NAME] [--port 5432] [--ssh-opts "..."]`
- `mix kamal.db.url [--env NAME] [--db-accessory NAME] [--port 5432] [--with-password]`

## Conventions

- Deploy config is read from `config/deploy.yml`.
- With destinations (`--env NAME`), deploy config is read from `config/deploy.yml` and
  `config/deploy.NAME.yml` and deep-merged (destination overrides base).
- Secrets follow Kamal destination semantics:
  - default: `.kamal/secrets`
  - named env: `.kamal/secrets.NAME` if present, otherwise `.kamal/secrets-common`

## Installer (Igniter)

If your project uses Igniter, you can run:

- `mix igniter.install kamal_ops`

The installer:

- ensures `/.kamal/secrets*` are ignored in `.gitignore` (so secrets aren't accidentally committed)
- installs `kamal_ops` as a dev-only, non-runtime dependency by default (`only: :dev`, `runtime: false`)

If you pass `--example`, it will also scaffold:

- `config/deploy.yml` and `config/deploy.prod.yml` (a minimal YAML structure that matches KamalOps task expectations)
- `.kamal/secrets` and `.kamal/secrets-common` (empty secret keys; still ignored by git)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `kamal_ops` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kamal_ops, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/kamal_ops>.
