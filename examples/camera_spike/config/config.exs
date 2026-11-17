# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

import Config

width = String.to_integer(System.get_env("CAMERA_WIDTH", "640"))
height = String.to_integer(System.get_env("CAMERA_HEIGHT", "480"))
frame_rate = String.to_integer(System.get_env("CAMERA_FPS", "10"))

# Which driver the robot declares. Read here rather than in the robot because
# `Application.compile_env/2` makes Mix recompile the robot when this changes,
# so exporting `CAMERA_DEVICE` and starting again is enough — the DSL is
# compile-time, but you don't have to think about that.
camera =
  cond do
    device = System.get_env("CAMERA_DEVICE") ->
      {BB.Camera.V4L, device: device, width: width, height: height, frame_rate: frame_rate}

    lavfi = System.get_env("CAMERA_LAVFI") ->
      {BB.Camera.V4L, lavfi: lavfi, width: width, height: height, frame_rate: frame_rate}

    true ->
      # Under `mix test` the synthetic camera produces a frame only when a test
      # asks for one, so nothing in the suite waits a plausible-looking number
      # of milliseconds for a picture. Everywhere else it free-runs.
      clock = if config_env() == :test, do: :external, else: {:rate, frame_rate}
      {BB.Camera.Synthetic, width: width, height: height, clock: clock}
  end

config :camera_spike, :camera, camera

# How long the MJPEG route waits for a camera. Shorter under `mix test`: the
# cases that exercise these are ones where no frame can arrive at all, so the
# timeout is the answer rather than a race.
config :camera_spike, :camera_stream,
  first_frame_timeout: if(config_env() == :test, do: 500, else: 5_000),
  frame_timeout: if(config_env() == :test, do: 500, else: 5_000)

config :camera_spike, CameraSpike.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: System.get_env("HOST", "localhost")],
  http: [
    ip: :inet.parse_address(~c"#{System.get_env("BIND", "127.0.0.1")}") |> elem(1),
    port: String.to_integer(System.get_env("PORT", "4001"))
  ],
  secret_key_base: String.duplicate("camera_spike_example_secret_key_base_", 2),
  live_view: [signing_salt: "camera_spike_salt"],
  check_origin: false,
  server: config_env() != :test

config :logger, level: String.to_existing_atom(System.get_env("LOG_LEVEL", "info"))
