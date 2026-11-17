# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.Application do
  @moduledoc false

  use Application

  require Logger

  @impl Application
  def start(_type, _args) do
    children = [
      %{id: CameraSpike.Robot, start: {BB.Supervisor, :start_link, [CameraSpike.Robot]}},
      CameraSpike.Endpoint
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: CameraSpike.Supervisor)

    announce()

    result
  end

  defp announce do
    {driver, opts} = CameraSpike.Robot.camera()
    url = CameraSpike.Endpoint.url()

    Logger.info("""

    camera_spike is up.

      camera:    #{inspect(driver)} #{inspect(opts)}
      dashboard: #{url}/robot
      stream:    #{url}/robot/__bb_camera__/eye/mjpeg
    """)
  end
end
