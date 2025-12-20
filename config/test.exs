# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

import Config

# Test endpoint configuration
config :bb_liveview, BB.LiveView.TestEndpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_security_purposes",
  server: false,
  live_view: [signing_salt: "test_signing_salt"]

# phoenix_test configuration
config :phoenix_test, :endpoint, BB.LiveView.TestEndpoint

# Reduce log noise in tests
config :logger, level: :warning
