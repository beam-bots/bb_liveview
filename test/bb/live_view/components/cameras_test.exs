# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.CamerasTest do
  use BB.LiveView.CameraCase

  describe "discovery" do
    test "lists the robot's cameras without being told about them", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera][data-camera=eye]")
      |> assert_has(".bb-camera-label", text: "Eye (link Head)")
      |> assert_has(".bb-camera-stream", text: ":jpeg 160×120 @ 10.0 fps")
    end

    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam, attached_to: {:joint, :wrist}}
         ]
    test "lists every camera on the robot", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera]", count: 2)
      |> assert_has(".bb-camera-label", text: "Gripper cam (joint Wrist)")
    end

    test "renders nothing about the driver's options", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> refute_has("*", text: "/dev/video0")
      |> refute_has("*", text: "hunter2")
    end

    test "a robot with no cameras says so", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has("[data-role=cameras-empty]", text: "This robot declares no cameras")
    end
  end

  describe "with no camera package installed" do
    setup do
      Application.put_env(:bb_liveview, :camera, BB.LiveView.Camera.BBCamera)
      :ok
    end

    test "the dashboard explains rather than failing", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=cameras-empty]", text: "No camera package installed")
    end

    test "a dashboard with no cameras is otherwise unchanged", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-widget", count: 7)
      |> assert_has(".bb-widget-title", text: "Safety")
    end
  end

  describe "an idle camera" do
    test "is not previewed, and nothing is asked of it", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-camera=eye][data-status=running]")
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Idle — nothing is capturing")
      |> assert_has("[data-role=camera-toggle]", text: "Start capturing")

      # The page made no request for frames, so the camera was never asked to
      # capture. Opening a dashboard must not switch every camera on.
      assert SyntheticCamera.consumer_count(:eye) == 0
      refute_received {:synthetic_camera, {:capture_started, :eye}}
    end

    test "previews once the viewer asks for it", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Start capturing")
      |> assert_has("[data-role=camera-preview][src^='/camera_robot/__bb_camera__/eye/mjpeg']")
      |> assert_has("[data-role=camera-toggle]", text: "Pause")
    end

    test "stays shown while the camera is still catching up", %{conn: conn} do
      # The `<img>` is what creates the demand, so it has to appear before the
      # camera reports capturing — otherwise nothing would ever start.
      conn
      |> visit("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Start capturing")
      |> assert_has("[data-camera=eye][data-status=running] [data-role=camera-preview]")
    end
  end

  describe "a camera that is already capturing" do
    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "previews without being asked", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-toggle]", text: "Pause")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "stays hidden if the viewer paused it", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Pause")
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
    end
  end

  describe "when the robot says a camera started capturing" do
    test "it appears, without anyone on this page asking", %{conn: conn} do
      session = visit(conn, "/camera_robot")

      refute_has(session, "[data-role=camera-preview]")

      session
      |> capture_started(:eye)
      |> assert_has("[data-role=camera-preview]")
    end

    test "a paused camera stays paused", %{conn: conn} do
      session =
        conn
        |> visit("/camera_robot")
        |> click_button("[data-role=camera-toggle]", "Start capturing")
        |> click_button("[data-role=camera-toggle]", "Pause")

      session
      |> capture_started(:eye)
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
    end

    test "a camera the viewer started stays shown", %{conn: conn} do
      session =
        conn
        |> visit("/camera_robot")
        |> click_button("[data-role=camera-toggle]", "Start capturing")

      session
      |> capture_started(:eye)
      |> assert_has("[data-role=camera-preview]")
    end
  end

  describe "cameras are independent" do
    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam}
         ]
    test "starting one leaves the other alone", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> click_button("[data-camera=eye] [data-role=camera-toggle]", "Start capturing")
      |> assert_has("[data-camera=eye] [data-role=camera-preview]")
      |> refute_has("[data-camera=gripper_cam] [data-role=camera-preview]")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-toggle]",
        text: "Start capturing"
      )
    end
  end

  describe "previews" do
    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "point at the camera route under the dashboard's own mount path", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera-preview][src^='/camera_robot/__bb_camera__/eye/mjpeg']")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :declared}]
    test "an offline camera is shown as offline, not hidden", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera][data-status=declared]")
      |> assert_has(".bb-camera-status", text: "Offline")
      |> assert_has("[data-role=camera-placeholder]",
        text: "declared in the robot but not running"
      )
      |> refute_has("[data-role=camera-preview]")
    end

    @tag cameras: [
           %{
             robot: BB.LiveView.CameraRobot,
             name: :depth,
             stream: %{format: {:raw, :rgb8}, width: 64, height: 48, frame_rate: nil}
           }
         ]
    test "a camera the browser can't render says why", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera-placeholder]", text: "can't be previewed as MJPEG")
      |> refute_has("[data-role=camera-preview]")
      |> refute_has("[data-role=camera-toggle]")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, stream: nil}]
    test "a camera that hasn't reported a format yet waits rather than failing", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has(".bb-camera-stream", text: "Format unknown")
      |> assert_has("[data-role=camera-placeholder]", text: "Waiting for the driver")
    end

    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam, status: :capturing}
         ]
    test "pausing one camera leaves the other's connection alone", %{conn: conn} do
      # Resuming changes the resumed camera's URL so the browser opens a fresh
      # request for it. Every other camera's `src` must stay exactly as it was,
      # or reviving one preview tears down and rebuilds all of them.
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-preview][src$='?g=0']")
      |> click_button("[data-camera=eye] [data-role=camera-toggle]", "Pause")
      |> click_button("[data-camera=eye] [data-role=camera-toggle]", "Resume")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-preview][src$='?g=0']")
      |> refute_has("[data-camera=eye] [data-role=camera-preview][src$='?g=0']")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "pausing drops the image, which is what closes the connection", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[data-role=camera-preview]")
      |> click_button("[data-role=camera-toggle]", "Pause")
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
      |> click_button("[data-role=camera-toggle]", "Resume")
      |> assert_has("[data-role=camera-preview]")
    end
  end

  # The dashboard forwards a camera's lifecycle events to this component, which
  # re-reads the camera list. Flipping the hub's status and handing the
  # LiveView the message the robot would have published takes the same path,
  # with no browser and no waiting.
  defp capture_started(session, camera) do
    :ok = SyntheticCamera.set_status(camera, :capturing)

    message = %BB.Message{
      frame_id: camera,
      robot: BB.LiveView.CameraRobot,
      monotonic_time: System.monotonic_time(),
      wall_time: System.system_time(:nanosecond),
      node: node(),
      payload: %BB.Message.Camera.BeginCapture{subscriber_count: 1}
    }

    PhoenixTest.unwrap(session, fn view ->
      send(view.pid, {:bb, [:sensor, :head, camera], message})
      Phoenix.LiveViewTest.render(view)
    end)
  end
end
