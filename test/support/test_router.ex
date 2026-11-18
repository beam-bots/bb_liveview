# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.TestRouter do
  @moduledoc """
  Test router for BB Dashboard integration tests.
  """

  use Phoenix.Router
  import Phoenix.LiveView.Router

  import Plug.Conn
  import Phoenix.Controller
  import BB.LiveView.Router

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
    bb_dashboard("/robot", robot: BB.LiveView.TestRobot)

    bb_dashboard("/camera_robot",
      robot: BB.LiveView.CameraRobot,
      camera_stream: [first_frame_timeout: 250, frame_timeout: 250]
    )

    bb_dashboard("/command_robot", robot: BB.LiveView.CommandRobot)
    bb_dashboard("/dev_robot", robot: Dev.TestRobot)
    bb_dashboard("/joint_robot", robot: BB.LiveView.JointRobot)
    bb_dashboard("/planar_robot", robot: BB.LiveView.PlanarRobot)
    bb_dashboard("/parameter_robot", robot: BB.LiveView.ParameterRobot)

    # The case that always worked: mounted at the root, where a root-absolute
    # asset URL happens to be correct.
    bb_dashboard("/", robot: BB.LiveView.RootRobot)
  end

  # A dashboard inside an outer scope: the macro only ever sees "/arm", so
  # anything that builds asset or camera URLs has to learn the "/admin" part
  # from the request rather than from the macro.
  scope "/admin" do
    pipe_through(:browser)
    bb_dashboard("/arm", robot: BB.LiveView.NestedRobot)
  end
end
