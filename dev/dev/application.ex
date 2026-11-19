# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Dev.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Dev.PubSub},
      %{
        id: BB.Supervisor,
        start: {BB.Supervisor, :start_link, [Dev.TestRobot]}
      },
      synthetic_camera(),
      DevWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Dev.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Stands in for `bb_camera` until the real package is installed: the
  # dashboard, the HTTP route and the browser all run the production path, and
  # only the bytes are invented. Two cameras so the dev server shows both
  # states — one capturing, one declared but offline.
  defp synthetic_camera do
    {BB.LiveView.SyntheticCamera,
     clock: {:rate, 10},
     cameras: [
       %{
         robot: Dev.TestRobot,
         name: :head_camera,
         path: [:sensor, :base_link, :head_camera],
         attached_to: {:link, :base_link}
       },
       %{
         robot: Dev.TestRobot,
         name: :gripper_camera,
         path: [:sensor, :wrist, :gripper_camera],
         attached_to: {:joint, :wrist},
         status: :declared
       }
     ]}
  end

  @impl true
  def config_change(changed, _new, removed) do
    DevWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
