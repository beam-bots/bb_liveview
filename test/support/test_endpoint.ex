# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.TestEndpoint do
  @moduledoc """
  Test endpoint for BB Dashboard integration tests.
  """

  use Phoenix.Endpoint, otp_app: :bb_liveview

  @session_options [
    store: :cookie,
    key: "_bb_liveview_test_key",
    signing_salt: "test_signing_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :bb_liveview,
    gzip: false,
    only: ~w(assets)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)

  plug(BB.LiveView.TestRouter)
end
