# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbLiveview.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  @router_content """
  defmodule TestWeb.Router do
    use TestWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, html: {TestWeb.Layouts, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    scope "/" do
      pipe_through :browser
      get "/", PageController, :home
    end
  end
  """

  @endpoint_content """
  defmodule TestWeb.Endpoint do
    use Phoenix.Endpoint, otp_app: :test

    socket "/live", Phoenix.LiveView.Socket

    plug Plug.RequestId
    plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

    plug Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Jason

    plug Plug.MethodOverride
    plug Plug.Head
    plug Plug.Session, store: :cookie, key: "_test_key", signing_salt: "test"
    plug TestWeb.Router
  end
  """

  @web_module_content """
  defmodule TestWeb do
    def router do
      quote do
        use Phoenix.Router
        import Plug.Conn
        import Phoenix.Controller
        import Phoenix.LiveView.Router
      end
    end

    defmacro __using__(which) when is_atom(which) do
      apply(__MODULE__, which, [])
    end
  end
  """

  describe "mix bb_liveview.install" do
    test "adds import to router" do
      test_project(
        app_name: :test,
        files: %{
          "lib/test_web/router.ex" => @router_content,
          "lib/test_web/endpoint.ex" => @endpoint_content,
          "lib/test_web.ex" => @web_module_content
        }
      )
      |> Igniter.compose_task("bb_liveview.install", [])
      |> apply_igniter!()
      |> assert_has_patch("lib/test_web/router.ex", """
      + | import BB.LiveView.Router
      """)
    end

    test "adds bb_dashboard to browser scope" do
      test_project(
        app_name: :test,
        files: %{
          "lib/test_web/router.ex" => @router_content,
          "lib/test_web/endpoint.ex" => @endpoint_content,
          "lib/test_web.ex" => @web_module_content
        }
      )
      |> Igniter.compose_task("bb_liveview.install", [])
      |> apply_igniter!()
      |> assert_has_patch("lib/test_web/router.ex", """
      + | bb_dashboard "/robot", robot: Test.Robot
      """)
    end

    test "adds Plug.Static to endpoint" do
      test_project(
        app_name: :test,
        files: %{
          "lib/test_web/router.ex" => @router_content,
          "lib/test_web/endpoint.ex" => @endpoint_content,
          "lib/test_web.ex" => @web_module_content
        }
      )
      |> Igniter.compose_task("bb_liveview.install", [])
      |> apply_igniter!()
      |> assert_has_patch("lib/test_web/endpoint.ex", """
      + | plug Plug.Static,
      + |   at: "/__bb_assets__",
      + |   from: {:bb_liveview, "priv/static"},
      + |   gzip: false
      """)
    end
  end
end
