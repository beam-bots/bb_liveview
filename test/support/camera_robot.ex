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
end
