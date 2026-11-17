# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.IntegrationTest do
  @moduledoc """
  The dashboard's camera path against the real packages.

  Nothing here is a double. `bb_camera` discovers a camera declared in a real
  robot's DSL, `BB.Camera.Media` hands over real JPEG frames, and the MJPEG
  route is reached through this example's own endpoint and router — the same
  code a browser hits. The seam-level tests in `bb_liveview` prove the
  dashboard behaves; these prove it is wired to the thing it claims to be.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2, put_private: 3]

  alias BB.Camera.Synthetic
  alias BB.LiveView.Camera
  alias BB.LiveView.Plugs.CameraStream
  alias CameraSpike.Robot

  @endpoint CameraSpike.Endpoint

  @stream_path "/robot/__bb_camera__/eye/mjpeg"

  setup do
    {:ok, conn: build_conn()}
  end

  describe "discovery" do
    test "finds the camera declared in the robot's DSL" do
      assert [camera] = Camera.discover(Robot)

      assert camera.name == :eye
      assert camera.attached_to == {:link, :base_link}
      assert camera.status in [:running, :capturing]
      assert camera.previewable?
      assert camera.stream.format == :jpeg
    end

    test "carries nothing the driver was configured with" do
      [camera] = Camera.discover(Robot)

      refute Map.has_key?(camera, :options)
      refute Map.has_key?(camera, :child_spec)
      refute camera |> inspect() |> String.contains?("/dev/")
    end

    test "resolves the name a URL carries, and only a name that exists" do
      assert {:ok, %{name: :eye}} = Camera.fetch(Robot, "eye")
      assert :error = Camera.fetch(Robot, "a_camera_that_was_never_declared")

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("a_camera_that_was_never_declared")
      end
    end
  end

  describe "the media session" do
    test "hands over real JPEG, newer each time" do
      {:ok, session} = Camera.open(Robot, :eye, format: :jpeg)
      await_capture(Robot, :eye)

      :ok = Synthetic.capture_frame(Robot, :eye)
      assert {:ok, frame} = Camera.next(session, 5_000)

      assert frame.format == :jpeg
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = frame.data

      :ok = Synthetic.capture_frame(Robot, :eye)
      assert {:ok, later} = Camera.next(session, 5_000)
      assert later.sequence > frame.sequence

      assert :ok = Camera.close(session)
    end

    test "says so rather than hanging when no frame is produced" do
      {:ok, session} = Camera.open(Robot, :eye, format: :jpeg)

      # Nothing captures: the clock is external and this test doesn't turn it.
      assert {:error, _reason} = Camera.next(session, 250)

      assert :ok = Camera.close(session)
    end
  end

  describe "the MJPEG route" do
    test "streams multipart JPEG through the router", %{conn: conn} do
      task = Task.async(fn -> dispatch(conn, @endpoint, :get, @stream_path) end)

      await_capture(Robot, :eye)
      :ok = Synthetic.capture_frame(Robot, :eye)

      conn = Task.await(task, 15_000)

      assert conn.status == 200

      assert get_resp_header(conn, "content-type") == [
               "multipart/x-mixed-replace; boundary=bbcameraframe"
             ]

      assert conn.resp_body =~ "--bbcameraframe"
      assert conn.resp_body =~ "Content-Type: image/jpeg"
      assert String.contains?(conn.resp_body, <<0xFF, 0xD8, 0xFF>>)
    end

    test "404s a camera the robot doesn't declare", %{conn: conn} do
      conn = dispatch(conn, @endpoint, :get, "/robot/__bb_camera__/nostril/mjpeg")

      assert conn.status == 404
    end

    test "503s before committing a 200 when nothing is produced", %{conn: conn} do
      conn = dispatch(conn, @endpoint, :get, @stream_path)

      assert conn.status == 503
      assert conn.resp_body == "Camera is not producing frames"
      refute conn.resp_body =~ "/dev/"
    end
  end

  describe "the dashboard" do
    test "previews the camera at the path it is mounted on", %{conn: conn} do
      {:ok, view, _initial} = live(conn, "/robot")

      # The dashboard sends itself a message on mount and renders its widgets
      # when it arrives. `render/1` is a synchronous call to the same process,
      # so it cannot overtake that message — no waiting involved.
      html = render(view)

      assert html =~ "Cameras"
      assert html =~ ~s(data-camera="eye")
      assert html =~ "/robot/__bb_camera__/eye/mjpeg"
    end
  end

  describe "the V4L driver, with no camera" do
    @describetag :ffmpeg

    setup do
      robot = CameraSpike.Test.LavfiRobot
      start_supervised!(%{id: robot, start: {BB.Supervisor, :start_link, [robot]}})
      {:ok, robot: robot}
    end

    test "is discovered like any other camera", %{robot: robot} do
      assert [%{name: :eye, previewable?: true}] = Camera.discover(robot)
    end

    test "hands real frames to the same media session", %{robot: robot} do
      {:ok, session} = Camera.open(robot, :eye, format: :jpeg)

      assert {:ok, frame} = Camera.next(session, 30_000)
      assert frame.format == :jpeg
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = frame.data

      assert :ok = Camera.close(session)
    end

    test "streams through the same Plug, from ffmpeg's own synthetic source", %{robot: robot} do
      # ffmpeg gets as long as it needs to start, then the route is given a
      # quarter second to find a *second* frame. The source emits one a second,
      # so there cannot be one, and the response ends after the first — a
      # camera that is simply slow, rather than a timer racing one.
      conn =
        :get
        |> Plug.Test.conn(@stream_path)
        |> Map.put(:params, %{"camera" => "eye"})
        |> put_private(:bb_camera_robot, robot)
        |> put_private(:bb_camera_stream, first_frame_timeout: 30_000, frame_timeout: 250)
        |> CameraStream.call(CameraStream.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "--bbcameraframe"
      assert conn.resp_body =~ "Content-Type: image/jpeg"
      assert String.contains?(conn.resp_body, <<0xFF, 0xD8, 0xFF>>)
    end
  end

  # The driver confirms capture asynchronously after the first consumer
  # arrives, so an immediate `capture_frame/2` races that answer. The robot
  # says when it has started.
  defp await_capture(robot, camera) do
    BB.subscribe(robot, [:sensor, :base_link, camera])

    receive do
      {:bb, _path, %BB.Message{payload: %BB.Message.Camera.BeginCapture{}}} -> :ok
    after
      5_000 -> flunk("#{inspect(robot)} never started capturing #{inspect(camera)}")
    end
  end
end
