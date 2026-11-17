# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.Test.LavfiRobot do
  @moduledoc """
  A robot whose camera is a real `BB.Camera.V4L` with no camera behind it.

  `lavfi: "testsrc2"` runs the whole driver — a real ffmpeg process, a real
  pipe, real JPEG framing — against one of ffmpeg's synthetic sources. It is
  the difference between "the V4L driver works" and "this machine has a
  webcam", and it is the only way to exercise that path in CI.
  """

  use BB

  settings do
    name(:camera_spike_lavfi)
  end

  topology do
    link :base_link do
      sensor(:eye, {BB.Camera.V4L, lavfi: "testsrc2", width: 320, height: 240, frame_rate: 1})
    end
  end
end
