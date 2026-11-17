# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.MixProject do
  use Mix.Project

  @moduledoc """
  A whole robot, a dashboard and a camera, wired together for real.
  """

  def project do
    [
      app: :camera_spike,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() == :prod,
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CameraSpike.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Everything beam-bots is a sibling checkout. `bb_camera` and
  # `bb_camera_v4l` are not published, so there is no version of this example
  # that resolves from Hex — which is the point: it exercises the packages as
  # they are, not as they were last released.
  defp deps do
    [
      {:bb, bb_dep()},
      {:bb_camera, path: "../../../bb_camera"},
      {:bb_camera_v4l, path: "../../../bb_camera_v4l"},
      {:bb_liveview, path: "../.."},

      # `bb_camera` explains this one: Membrane's `ratio` would otherwise hold
      # `decimal` down on a 2.x with open advisories.
      {:decimal, "~> 3.0", override: true},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp bb_dep do
    case System.get_env("BB_VERSION") do
      "main" -> [git: "https://github.com/beam-bots/bb.git", override: true]
      version when is_binary(version) and version != "local" -> "~> #{version}"
      _local_or_unset -> [path: "../../../bb", override: true]
    end
  end
end
