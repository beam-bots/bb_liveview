# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :camera_spike

  @session_options [
    store: :cookie,
    key: "_camera_spike_key",
    signing_salt: "camera_spike_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.Session, @session_options)
  plug(CameraSpike.Router)
end
