# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.CameraCase do
  @moduledoc """
  Test case for the camera preview path.

  Starts `BB.LiveView.SyntheticCamera`, points the `BB.LiveView.Camera` seam at
  it for the duration of the test, and has it report to the test process — so
  every test can wait for the thing it cares about (a stream being watched, a
  signalling message arriving) instead of waiting a length of time.

  Override the cameras for a test with `@tag cameras: [...]`, and stand in for
  an application without `bb_camera_webrtc` with `@tag webrtc?: false`, or
  without `bb_camera` at all with `@tag available?: false`.
  """

  use ExUnit.CaseTemplate

  alias BB.LiveView.SyntheticCamera

  using do
    quote do
      import PhoenixTest

      alias BB.LiveView.Camera
      alias BB.LiveView.CameraRobot
      alias BB.LiveView.SyntheticCamera

      @endpoint BB.LiveView.TestEndpoint
    end
  end

  setup tags do
    cameras =
      Map.get(tags, :cameras, [
        %{
          robot: BB.LiveView.CameraRobot,
          name: :eye,
          path: [:sensor, :head, :eye],
          attached_to: {:link, :head}
        }
      ])

    start_supervised!(
      {SyntheticCamera,
       available?: Map.get(tags, :available?, true),
       cameras: cameras,
       report_to: self(),
       webrtc?: Map.get(tags, :webrtc?, true)}
    )

    previous = Application.fetch_env(:bb_liveview, :camera)
    Application.put_env(:bb_liveview, :camera, SyntheticCamera)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bb_liveview, :camera, value)
        :error -> Application.delete_env(:bb_liveview, :camera)
      end
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
