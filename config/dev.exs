# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

import Config

# Development configuration
config :logger, level: :debug

# esbuild configuration
config :esbuild, :version, "0.24.2"

# Dev endpoint configuration
config :bb_liveview, DevWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: Dev.PubSub,
  live_view: [signing_salt: "bb_dev_live_view_salt"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_that_is_at_least_64_bytes_long_for_security_purposes_only",
  server: true,
  code_reloader: true,
  watchers: []

# Enable live_reload for development
config :bb_liveview, DevWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"lib/bb/live_view/.*(ex|heex)$",
      ~r"dev/.*(ex|heex)$",
      ~r"priv/static/.*(js|css)$"
    ]
  ]
