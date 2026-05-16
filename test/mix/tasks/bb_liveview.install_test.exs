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

  @endpoint """
  defmodule TestWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :test

    plug Plug.Static,
      at: "/",
      from: :test,
      gzip: false
  end
  """

  @phx_files %{
    "lib/test_web/router.ex" => @router,
    "lib/test_web/endpoint.ex" => @endpoint
  }

  describe "Phoenix project" do
    defp phx_with_robot do
      test_project(files: @phx_files)
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
      test_project(files: @phx_files)
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

    test "adds a Plug.Static for /__bb_assets__ to the endpoint" do
      igniter =
        phx_with_robot()
        |> Igniter.compose_task("bb_liveview.install")
        |> apply_igniter!()

      endpoint =
        igniter.rewrite
        |> Rewrite.source!("lib/test_web/endpoint.ex")
        |> Rewrite.Source.get(:content)

      assert endpoint =~ ~s|at: "/__bb_assets__"|
      assert endpoint =~ ~s|from: {:bb_liveview, "priv/static"}|
    end

    test "endpoint patch is idempotent" do
      phx_with_robot()
      |> Igniter.compose_task("bb_liveview.install")
      |> apply_igniter!()
      |> Igniter.compose_task("bb_liveview.install")
      |> assert_unchanged("lib/test_web/endpoint.ex")
    end

    test "bb_assets Plug.Static is inserted BEFORE the generic Plug.Static" do
      igniter =
        phx_with_robot()
        |> Igniter.compose_task("bb_liveview.install")
        |> apply_igniter!()

      endpoint =
        igniter.rewrite
        |> Rewrite.source!("lib/test_web/endpoint.ex")
        |> Rewrite.Source.get(:content)

      bb_assets_pos = :binary.match(endpoint, "/__bb_assets__") |> elem(0)
      generic_pos = :binary.match(endpoint, ~s|from: :test|) |> elem(0)

      assert bb_assets_pos < generic_pos,
             "bb_assets Plug.Static must precede the generic Plug.Static"
    end
  end

  describe "non-Phoenix project" do
    test "prints a manual mount snippet when user declines bootstrap" do
      with_mix_shell_response(false, fn ->
        test_project()
        |> Igniter.compose_task("bb.install")
        |> apply_igniter!()
        |> Igniter.compose_task("bb_liveview.install")
        |> assert_has_notice(&String.contains?(&1, "bb_dashboard"))
      end)
    end

    test "--auto-phoenix bootstraps a Phoenix endpoint and router" do
      igniter =
        test_project()
        |> Igniter.compose_task("bb.install")
        |> apply_igniter!()
        |> Igniter.compose_task("bb_liveview.install", ["--auto-phoenix"])
        |> apply_igniter!()

      mix_exs =
        igniter.rewrite
        |> Rewrite.source!("mix.exs")
        |> Rewrite.Source.get(:content)

      assert mix_exs =~ ":phoenix"
      assert mix_exs =~ ":phoenix_live_view"
    end

    test "--auto-phoenix does NOT add ecto, mailer, gettext, or live_dashboard" do
      igniter =
        test_project()
        |> Igniter.compose_task("bb.install")
        |> apply_igniter!()
        |> Igniter.compose_task("bb_liveview.install", ["--auto-phoenix"])
        |> apply_igniter!()

      mix_exs =
        igniter.rewrite
        |> Rewrite.source!("mix.exs")
        |> Rewrite.Source.get(:content)

      refute mix_exs =~ ":ecto_sql"
      refute mix_exs =~ ":postgrex"
      refute mix_exs =~ ":swoosh"
      refute mix_exs =~ ":gettext"
      refute mix_exs =~ ":phoenix_live_dashboard"
    end

    test "--auto-phoenix mounts the dashboard in the generated router" do
      igniter =
        test_project()
        |> Igniter.compose_task("bb.install")
        |> apply_igniter!()
        |> Igniter.compose_task("bb_liveview.install", ["--auto-phoenix"])
        |> apply_igniter!()

      router =
        igniter.rewrite
        |> Rewrite.source!("lib/test_web/router.ex")
        |> Rewrite.Source.get(:content)

      assert router =~ "import BB.LiveView.Router"
      assert router =~ "bb_dashboard"
    end
  end

  # Swaps `Mix.shell` to `Mix.Shell.Process` and preloads `response` as the
  # next answer to `yes?/1`. Required because `ex_check` runs without a TTY,
  # so the default IO shell raises on `yes?/1` instead of returning the
  # response a real user would type.
  defp with_mix_shell_response(response, fun) do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :yes?, response})

    try do
      fun.()
    after
      Mix.shell(previous)
      flush_mix_shell_mailbox()
    end
  end

  defp flush_mix_shell_mailbox do
    receive do
      {:mix_shell, _, _} -> flush_mix_shell_mailbox()
      {:mix_shell_input, _, _} -> flush_mix_shell_mailbox()
    after
      0 -> :ok
    end
  end
end
