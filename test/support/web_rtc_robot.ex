# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.WebRTCRobot do
  @moduledoc """
  A real robot with a real `bb_camera` camera, for testing the default camera
  implementation against `bb_camera` and `bb_camera_webrtc` themselves.
  """
  use BB

  settings do
    name(:bb_liveview_web_rtc_robot)
  end

  topology do
    link :base do
      sensor(:eye, {BB.Camera.Synthetic, width: 160, height: 120, clock: {:rate, 30}})
    end
  end
end
