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
- `mix kamal.db.tunnel [--env NAME] [--db-accessory NAME] [--port 5432] [--ssh-opts \"...\"] [--role ROLE]`
- `mix kamal.db.url [--env NAME] [--db-accessory NAME] [--port 5432] [--print-url] [--with-password]`

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

If you pass `--init`, it will:

- check that the `kamal` executable exists on your system (fails if missing)
- ask for (or use) `--host`, then scaffold a minimal `config/deploy.yml` that should be close to a working setup

Example:

- `mix igniter.install kamal_ops --init --host 1.2.3.4`

If the installer detects Postgres usage (heuristic: common deps like `postgrex`, `ecto_sql`, `ash_postgres`),
it will also scaffold a Postgres accessory and generate `POSTGRES_PASSWORD` and `DATABASE_URL` in `.kamal/secrets`.
You can force/disable this with `--db` / `--no-db`.

If you pass `--example`, it will also scaffold:

- `config/deploy.yml` and `config/deploy.prod.yml` (a minimal YAML structure to get to a working Kamal setup fast)
- `.kamal/secrets` and `.kamal/secrets-common` (empty secret files; still ignored by git)

### Minimal Kamal Setup (Single Server)

For a "hello world" Kamal setup, you usually only need:

- a server IP (or hostname)
- SSH access (Kamal defaults to connecting as `root` if you omit `ssh.user`)

The scaffolded `config/deploy.yml` uses Kamal's "local registry" (`registry.server: localhost:5000`)
so you can avoid setting up an external Docker registry account on day 1.

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
