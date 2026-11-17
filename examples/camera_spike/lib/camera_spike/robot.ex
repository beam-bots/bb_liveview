# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.Robot do
  @moduledoc """
  A robot with one link and one camera on it.

  The camera is declared like any other sensor. Which driver it is comes from
  `config/config.exs`, which reads the environment — `BB.Camera.Synthetic` by
  default, `BB.Camera.V4L` when `CAMERA_DEVICE` or `CAMERA_LAVFI` is set.
  Nothing else in the example changes between them, which is the thing worth
  demonstrating: the dashboard does not know or care which camera it is
  looking at.
  """

  use BB

  @camera Application.compile_env(:camera_spike, :camera)

  settings do
    name(:camera_spike)
  end

  topology do
    link :base_link do
      sensor(:eye, @camera)
    end
  end

  @doc "The camera driver and options this robot was compiled with."
  @spec camera() :: {module, keyword}
  def camera, do: @camera
end
