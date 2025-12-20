# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.MixProject do
  use Mix.Project

  @moduledoc """
  Interactive LiveView-based dashboard for Beam Bots-powered robots.
  """

  @version "0.1.0"

  def project do
    [
      aliases: aliases(),
      app: :bb_liveview,
      consolidate_protocols: Mix.env() == :prod,
      deps: deps(),
      description: @moduledoc,
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      listeners: listeners(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  defp listeners(:dev), do: [Phoenix.CodeReloader]
  defp listeners(_), do: []

  def application, do: application(Mix.env())

  def application(:dev) do
    [
      extra_applications: [:logger],
      mod: {Dev.Application, []}
    ]
  end

  def application(_) do
    [
      extra_applications: [:logger]
    ]
  end

  defp dialyzer, do: [plt_add_apps: [:ex_unit]]

  defp package do
    [
      maintainers: ["James Harton <james@harton.nz>"],
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => "https://github.com/beam-bots/bb_liveview",
        "Sponsor" => "https://github.com/sponsors/jimsynz"
      },
      files: ~w(
        lib
        priv/static
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE*
        LICENSES
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        ["README.md", "CHANGELOG.md"]
        |> Enum.concat(Path.wildcard("documentation/**/*.{md,livemd,cheatmd}")),
      groups_for_extras: [
        Tutorials: ~r/tutorials\//
      ],
      source_ref: "main",
      source_url: "https://github.com/beam-bots/bb_liveview"
    ]
  end

  defp aliases do
    [
      "assets.setup": ["cmd --cd assets npm install"],
      "assets.build": [
        "cmd --cd assets npm run build",
        "cmd --cd assets npm run build:css"
      ],
      "assets.deploy": [
        "cmd --cd assets npm run build -- --minify",
        "cmd --cd assets npm run build:css"
      ],
      "hex.build": ["assets.deploy", "hex.build"],
      "hex.publish": ["assets.deploy", "hex.publish"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bb, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug, "~> 1.16"},

      # Build tools (dev only)
      {:bandit, "~> 1.0", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:phoenix_live_reload, "~> 1.5", only: :dev},

      # dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:floki, "~> 0.36", only: :test},
      {:git_ops, "~> 2.9", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.2", only: :test, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:phoenix_test, "~> 0.9", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "dev"]
  defp elixirc_paths(:dev), do: ["lib", "test/support", "dev"]
  defp elixirc_paths(_), do: ["lib"]
end
