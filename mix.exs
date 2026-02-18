defmodule KamalOps.MixProject do
  use Mix.Project

  @source_url "https://github.com/vkryukov/kamal_ops"
  @version "0.1.0"

  def project do
    [
      app: :kamal_ops,
      version: @version,
      elixir: "~> 1.15",
      description: "Mix tasks and helpers for operating Kamal deployments from Elixir projects.",
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: "kamal_ops",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Kamal" => "https://kamal-deploy.org/"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      # Optional for consumers, but available in all envs when explicitly included.
      # This allows `kamal_ops` to compile against Igniter task APIs in host projects.
      {:igniter, "~> 0.6", optional: true, runtime: false},
      {:ex_doc, "~> 0.37", only: [:dev, :docs], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
