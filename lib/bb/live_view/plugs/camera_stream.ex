# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Plugs.CameraStream do
  @moduledoc """
  Streams one camera to one browser as `multipart/x-mixed-replace` — MJPEG.

  Mounted by `BB.LiveView.Router.bb_dashboard/2` inside the same scope as the
  dashboard itself, so it runs through whatever pipeline the host put in front
  of the dashboard. It is not a separate server and grants no access the
  dashboard doesn't: if the dashboard is behind a `require_admin` plug, so is
  this; if the dashboard is public, so is this. The URL is not a credential and
  must not be treated as one.

  ## Why MJPEG

  It is the smallest thing that works. Every browser renders it in an `<img>`
  with no JavaScript, no media source extensions and no WebRTC signalling, and
  the camera hub already hands out whole JPEG frames. The cost is bandwidth —
  every frame is a complete image — which is why this is a preview and not a
  video transport.

  ## Backpressure

  One frame is asked for at a time, and the next is only asked for once the
  previous one has been written. `BB.Camera.Media.next/2` returns a frame
  strictly newer than the last, so the loop advances at the camera's capture
  rate rather than spinning on repeats, and the camera hub keeps exactly one
  latest frame per camera: a browser that reads slowly simply misses frames.

  That bounds the parts this code owns — the media session and this process's
  mailbox, neither of which grows. It does not abolish buffering further down:
  the web server still holds whatever it has accepted for the socket, and a
  frame handed to `chunk/2` is out of our hands. What it guarantees is that a
  stalled reader cannot make the *camera side* accumulate.

  ## This path does not go through Membrane

  Frames go camera hub → this process → `Plug.Conn.chunk/2`. `bb_camera` ships
  a `Membrane.Source` that maps Membrane's demand onto the same media session,
  and a transport that needs real muxing (fragmented MP4, WebRTC) should be
  built on it. A preview that is already a stream of complete JPEGs gains
  nothing from a pipeline, so it doesn't have one.

  ## Failure before commitment

  The status is decided before a byte is sent: the camera is resolved, the
  session opened with `format: :jpeg` asserted, and the *first frame* waited
  for and checked, all before `send_chunked/2`. A camera that is declared but
  offline, or alive but producing nothing, answers 503 — rather than a 200 that
  hangs and leaves the browser showing a broken image forever.

  A camera whose driver can only learn its real format from the hardware
  reports no stream info until it captures. That is not a refusal: such a
  camera is opened anyway and judged on the frame it produces.
  """

  @behaviour Plug

  import Plug.Conn

  alias BB.LiveView.Camera

  @boundary "bbcameraframe"
  @default_first_frame_timeout 5_000
  @default_frame_timeout 10_000

  @impl Plug
  def init(opts) when is_list(opts), do: opts
  def init(_opts), do: []

  @impl Plug
  def call(conn, opts) do
    opts = Keyword.merge(opts, conn.private[:bb_camera_stream] || [])

    with {:ok, robot} <- fetch_robot(conn),
         {:ok, camera} <- fetch_camera(conn, robot),
         :ok <- previewable(camera) do
      stream(conn, robot, camera, opts)
    else
      {:error, status, message} -> refuse(conn, status, message)
    end
  end

  defp fetch_robot(conn) do
    case conn.private[:bb_camera_robot] do
      nil -> {:error, 500, "No robot configured for this camera route"}
      robot -> {:ok, robot}
    end
  end

  defp fetch_camera(conn, robot) do
    case Camera.fetch(robot, conn.params["camera"]) do
      {:ok, camera} -> {:ok, camera}
      :error -> {:error, 404, "No such camera"}
    end
  end

  # Only a camera that has *said* it is something else is turned away here. A
  # camera that hasn't reported a format yet gets opened and judged on its
  # first frame, because some drivers only learn the format from the device.
  defp previewable(%{stream: %{format: format}}) when format != :jpeg,
    do: {:error, 415, "Camera streams #{inspect(format)}; only :jpeg previews as MJPEG"}

  defp previewable(_camera), do: :ok

  defp stream(conn, robot, camera, opts) do
    case Camera.open(robot, camera.name, format: :jpeg) do
      {:ok, session} -> with_session(conn, session, opts)
      {:error, reason} -> refuse(conn, 503, describe(reason))
    end
  end

  defp with_session(conn, session, opts) do
    timeout = Keyword.get(opts, :first_frame_timeout, @default_first_frame_timeout)

    # Every way the first frame can fail to arrive — a timeout, a capture that
    # ended, a driver that failed, a hub that died — means the same thing to
    # the browser, and the reason is the camera's business, not the response's.
    case Camera.next(session, timeout) do
      {:ok, frame} -> first_frame(conn, session, frame, opts)
      {:error, _reason} -> refuse(conn, 503, "Camera is not producing frames")
    end
  after
    Camera.close(session)
  end

  # The session was opened with `format: :jpeg` asserted, but settings can move
  # after discovery and a driver can renegotiate on first capture, so the bytes
  # themselves get the last word — before any status is committed.
  defp first_frame(conn, session, frame, opts) do
    if jpeg?(frame) do
      conn
      |> put_resp_header("content-type", "multipart/x-mixed-replace; boundary=#{@boundary}")
      |> put_resp_header("cache-control", "no-store, no-cache, private, max-age=0")
      |> put_resp_header("pragma", "no-cache")
      |> send_chunked(200)
      |> write_frames(frame, session, Keyword.get(opts, :frame_timeout, @default_frame_timeout))
    else
      refuse(conn, 415, "Camera produced #{inspect(frame.format)}; only :jpeg previews as MJPEG")
    end
  end

  defp write_frames(conn, frame, session, timeout) do
    case write_frame(conn, frame) do
      {:ok, conn} -> continue_frames(conn, session, timeout)
      {:error, _closed} -> conn
    end
  end

  # Every error from `next/2` — timeout, end of capture, capture failure, a
  # dead hub — means the same thing here: stop streaming to this browser. The
  # response has already been committed, so ending it cleanly is all that's
  # left, and a camera that disappears can't leave the route hanging.
  defp continue_frames(conn, session, timeout) do
    case Camera.next(session, timeout) do
      {:ok, frame} ->
        if jpeg?(frame), do: write_frames(conn, frame, session, timeout), else: conn

      {:error, _reason} ->
        conn
    end
  end

  defp write_frame(conn, frame) do
    part = [
      "--",
      @boundary,
      "\r\nContent-Type: image/jpeg\r\nContent-Length: ",
      Integer.to_string(byte_size(frame.data)),
      "\r\n\r\n",
      frame.data,
      "\r\n"
    ]

    chunk(conn, part)
  end

  defp jpeg?(%{format: :jpeg, data: data}) when is_binary(data), do: true
  defp jpeg?(_frame), do: false

  # Deliberately coarse. A camera error can name the device it failed to open
  # or the URL it was refused by, and this response goes to a browser; the
  # detail belongs in the logs and the dashboard, not in the stream's body.
  defp describe(:no_camera_implementation), do: "No camera implementation installed"
  defp describe(_reason), do: "Camera unavailable"

  defp refuse(conn, status, message) do
    conn
    |> put_resp_header("content-type", "text/plain; charset=utf-8")
    |> send_resp(status, message)
    |> halt()
  end
end
