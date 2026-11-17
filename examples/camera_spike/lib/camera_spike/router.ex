# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.Router do
  @moduledoc """
  One dashboard, mounted at `/robot`.

  The camera stream route is created by `bb_dashboard/2` inside this same
  scope, so it goes through the `:browser` pipeline exactly as the dashboard
  does. Add an authentication plug to that pipeline and the stream is behind it
  too; this example has none, so both are open.
  """

  use Phoenix.Router

  @camera_stream Application.compile_env(:camera_spike, :camera_stream, [])

  import BB.LiveView.Router
  import Phoenix.Controller
  import Phoenix.LiveView.Router
  import Plug.Conn

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {BB.LiveView.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    bb_dashboard("/robot", robot: CameraSpike.Robot, camera_stream: @camera_stream)
  end
end
