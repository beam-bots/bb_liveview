# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Plugs.CameraStreamTest do
  use BB.LiveView.CameraCase

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias BB.LiveView.SyntheticCamera.Frames

  @boundary "bbcameraframe"
  @stream_path "/camera_robot/__bb_camera__/eye/mjpeg"

  describe "refusals" do
    test "404s a camera the robot doesn't declare", %{conn: conn} do
      conn = get(conn, "/camera_robot/__bb_camera__/nostril/mjpeg")

      assert conn.status == 404
      assert conn.resp_body == "No such camera"
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :declared}]
    test "503s a camera that is declared but not running", %{conn: conn} do
      conn = get(conn, @stream_path)

      assert conn.status == 503
    end

    @tag cameras: [
           %{
             robot: BB.LiveView.CameraRobot,
             name: :eye,
             stream: %{format: {:raw, :rgb8}, width: 64, height: 48, frame_rate: nil}
           }
         ]
    test "415s a camera whose format can't be previewed", %{conn: conn} do
      conn = get(conn, @stream_path)

      assert conn.status == 415
      assert conn.resp_body =~ "only :jpeg"
    end

    test "503s rather than committing a 200 to a camera that never produces", %{conn: conn} do
      # Nothing ever captures on this camera, so the first frame cannot arrive.
      # The route gives up and says so instead of answering 200 and hanging.
      conn = get(conn, @stream_path)

      assert conn.status == 503
      assert conn.resp_body == "Camera is not producing frames"
      assert_receive {:synthetic_camera, {:consumer_released, :eye, :closed}}
    end

    test "a refusal leaks nothing about the device", %{conn: conn} do
      conn = get(conn, @stream_path)

      refute conn.resp_body =~ "/dev/video0"
      refute conn.resp_body =~ "hunter2"
    end
  end

  describe "streaming" do
    test "writes each frame as a multipart JPEG part", %{conn: conn} do
      task = request_stream(conn)

      assert_receive {:synthetic_camera, {:capture_started, :eye}}

      frames = capture_frames(3)

      :ok = SyntheticCamera.stop_capture(:eye)
      conn = Task.await(task)

      assert conn.status == 200

      assert get_resp_header(conn, "content-type") == [
               "multipart/x-mixed-replace; boundary=#{@boundary}"
             ]

      assert ["no-store, no-cache, private, max-age=0"] =
               get_resp_header(conn, "cache-control")

      assert parts(conn.resp_body) == Enum.map(frames, &byte_size/1)
      assert conn.resp_body =~ "Content-Type: image/jpeg"

      Enum.each(frames, fn frame -> assert String.contains?(conn.resp_body, frame) end)
    end

    test "ends the response when the camera stops rather than hanging", %{conn: conn} do
      task = request_stream(conn)

      assert_receive {:synthetic_camera, {:capture_started, :eye}}
      capture_frames(1)

      :ok = SyntheticCamera.stop_capture(:eye)

      assert %{status: 200} = Task.await(task)
      assert_receive {:synthetic_camera, {:consumer_released, :eye, :closed}}
      assert SyntheticCamera.consumer_count(:eye) == 0
    end

    test "asks for one frame at a time", %{conn: conn} do
      task = request_stream(conn)

      assert_receive {:synthetic_camera, {:capture_started, :eye}}
      assert_receive {:synthetic_camera, {:demand, :eye}}

      # The route has one frame outstanding and will not ask for another until
      # it has written this one, so pushing the conversation forward
      # synchronously must not turn up a second demand.
      assert SyntheticCamera.consumer_count(:eye) == 1
      refute_received {:synthetic_camera, {:demand, :eye}}

      :ok = SyntheticCamera.stop_capture(:eye)
      Task.await(task)
    end

    test "releases the consumer when the browser goes away", %{conn: conn} do
      # An unlinked process stands in for a connection that dies mid-stream
      # without the plug's cleanup ever running.
      pid = spawn(fn -> dispatch(conn, @endpoint, :get, @stream_path) end)

      assert_receive {:synthetic_camera, {:capture_started, :eye}}
      assert_receive {:synthetic_camera, {:demand, :eye}}

      Process.exit(pid, :kill)

      assert_receive {:synthetic_camera, {:consumer_released, :eye, :owner_down}}
      assert_receive {:synthetic_camera, {:capture_stopped, :eye}}
      assert SyntheticCamera.consumer_count(:eye) == 0
    end
  end

  defp capture_frames(count) do
    Enum.map(1..count, fn index ->
      assert_receive {:synthetic_camera, {:demand, :eye}}
      :ok = SyntheticCamera.capture(:eye)
      Frames.at(index - 1)
    end)
  end

  defp parts(body) do
    body
    |> String.split("--#{@boundary}\r\n")
    |> Enum.drop(1)
    |> Enum.map(fn part ->
      [_, length] = Regex.run(~r/Content-Length: (\d+)/, part)
      String.to_integer(length)
    end)
  end

  defp request_stream(conn) do
    Task.async(fn -> dispatch(conn, @endpoint, :get, @stream_path) end)
  end
end
