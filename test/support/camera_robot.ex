# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.CameraRobot do
  @moduledoc """
  A mock robot used by the camera tests.

  Camera discovery is answered by whatever `BB.LiveView.Camera` implementation
  is configured, not by this module, so all this has to do is look like a robot.
  """

  def robot do
    %{
      name: "CameraRobot",
      links: %{},
      joints: %{},
      state: :idle
    }
  end

  @doc "ICE servers for the dashboard mounted with them, read on every mount."
  def ice_servers do
    [%{urls: "turn:turn.example.com:3478", username: "robot", credential: "secret"}]
  end
end
