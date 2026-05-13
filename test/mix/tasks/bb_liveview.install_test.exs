# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbLiveview.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  @router """
  defmodule TestWeb.Router do
    use Phoenix.Router

    pipeline :browser do
      plug(:accepts, ["html"])
    end

    scope "/", TestWeb do
      pipe_through(:browser)

      get("/", PageController, :home)
    end
  end
  """

  describe "Phoenix project" do
    defp phx_with_robot do
      test_project(files: %{"lib/test_web/router.ex" => @router})
      |> Igniter.compose_task("bb.install")
      |> apply_igniter!()
    end

    test "mounts the dashboard inside a :browser-piped scope" do
      phx_with_robot()
      |> Igniter.compose_task("bb_liveview.install")
      |> assert_has_patch("lib/test_web/router.ex", """
      + |  scope "/" do
      + |    pipe_through([:browser])
      + |    import BB.LiveView.Router
      + |    bb_dashboard("/", robot: Test.Robot)
      + |  end
      """)
    end

    test "uses a custom path when --path is given" do
      phx_with_robot()
      |> Igniter.compose_task("bb_liveview.install", ["--path", "/robot"])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |    bb_dashboard("/robot", robot: Test.Robot)
      """)
    end

    test "targets a specific robot module via --robot" do
      test_project(files: %{"lib/test_web/router.ex" => @router})
      |> Igniter.compose_task("bb.add_robot", ["--robot", "Test.Arms.Left"])
      |> apply_igniter!()
      |> Igniter.compose_task("bb_liveview.install", ["--robot", "Test.Arms.Left"])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |    bb_dashboard("/", robot: Test.Arms.Left)
      """)
    end

    test "imports bb_liveview into .formatter.exs" do
      phx_with_robot()
      |> Igniter.compose_task("bb_liveview.install")
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:bb_liveview, :bb]
      """)
    end
  end

  describe "non-Phoenix project" do
    test "prints a manual mount snippet" do
      test_project()
      |> Igniter.compose_task("bb.install")
      |> apply_igniter!()
      |> Igniter.compose_task("bb_liveview.install")
      |> assert_has_notice(&String.contains?(&1, "bb_dashboard"))
    end
  end
end
