# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Router do
  @moduledoc """
  Provides router helpers for mounting the BB Dashboard.

  ## Usage

  In your Phoenix router:

      import BB.LiveView.Router

      scope "/" do
        pipe_through :browser
        bb_dashboard "/robot", robot: MyRobot
      end

  The dashboard can be mounted multiple times at different paths for different robots:

      bb_dashboard "/arm", robot: ArmRobot
      bb_dashboard "/base", robot: BaseRobot

  ## Options

    * `:robot` - Required. The robot module to control. Must define a `robot/0` function.
    * `:camera_stream` - Optional. Keyword options for `BB.LiveView.Plugs.CameraStream`,
      which serves camera previews from this same scope:
      `:first_frame_timeout` (how long a camera has to produce its first frame
      before the request is refused with a 503, default 5000ms) and
      `:frame_timeout` (how long a stalled camera is given before the response
      is ended, default 10000ms).

  ## Cameras

  The macro also mounts `BB.LiveView.Plugs.CameraStream` at
  `<path>/__bb_camera__/:camera/mjpeg`, inside the same scope, so camera
  previews pass through whatever pipeline guards the dashboard. The dashboard
  builds those URLs from the path it is mounted at, so nothing needs
  configuring — but note that the stream is a plain HTTP response: it is as
  protected as the pipeline makes it, and no more. A preview URL is not a
  credential.

  ## Authentication

  Protect the dashboard using standard Phoenix pipelines:

      pipeline :admin do
        plug MyAppWeb.RequireAdmin
      end

      scope "/admin" do
        pipe_through [:browser, :admin]
        bb_dashboard "/robot", robot: MyRobot
      end
  """

  @doc """
  Defines routes for mounting the BB Dashboard at the given path.

  See the module documentation for usage examples.
  """
  defmacro bb_dashboard(path, opts) do
    quote bind_quoted: binding() do
      robot = Keyword.fetch!(opts, :robot)
      camera_stream = Keyword.get(opts, :camera_stream, [])

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]

        # Asset routes
        get(
          "/__bb_assets__/:file",
          BB.LiveView.Plugs.Static,
          :call,
          as: :bb_dashboard_asset,
          private: %{bb_dashboard_asset: true}
        )

        # Inside the same scope, so the host's pipeline guards the camera
        # stream exactly as it guards the dashboard.
        get(
          "/__bb_camera__/:camera/mjpeg",
          BB.LiveView.Plugs.CameraStream,
          [],
          as: :bb_dashboard_camera,
          private: %{bb_camera_robot: robot, bb_camera_stream: camera_stream}
        )

        live_session :"bb_dashboard_#{robot}",
          on_mount: [{BB.LiveView.Hooks.AssignRobot, robot}],
          root_layout: {BB.LiveView.Layouts, :root} do
          live("/", BB.LiveView.DashboardLive, :index)
        end
      end
    end
  end
end
