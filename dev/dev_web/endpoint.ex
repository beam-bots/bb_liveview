# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule DevWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :bb_liveview

  @session_options [
    store: :cookie,
    key: "_bb_liveview_dev_key",
    signing_salt: "bb_dev_salt"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :bb_liveview,
    gzip: false,
    only: ~w(assets)

  # Serve BB LiveView bundled assets before CSRF protection
  plug Plug.Static,
    at: "/__bb_assets__",
    from: {:bb_liveview, "priv/static"},
    gzip: false

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug DevWeb.Router
end
