# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.CameraCase do
  @moduledoc """
  Test case for the camera preview path.

  Starts `BB.LiveView.SyntheticCamera`, points the `BB.LiveView.Camera` seam at
  it for the duration of the test, and registers the test process to receive
  hub events — so every test can wait for the thing it cares about (a consumer
  opening, a frame being demanded, a consumer being released) instead of
  waiting a length of time.

  Override the cameras for a test with `@tag cameras: [...]`.
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

    start_supervised!({SyntheticCamera, cameras: cameras, clock: :external})

    previous = Application.fetch_env(:bb_liveview, :camera)
    Application.put_env(:bb_liveview, :camera, SyntheticCamera)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bb_liveview, :camera, value)
        :error -> Application.delete_env(:bb_liveview, :camera)
      end
    end)

    :ok = SyntheticCamera.watch(self())

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
