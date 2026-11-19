# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.CamerasTest do
  use BB.LiveView.CameraCase

  describe "discovery" do
    test "lists the robot's cameras without being told about them", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
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
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-view-toggle]", "Compare all")
      |> assert_has("[data-role=camera]", count: 2)
      |> assert_has(".bb-camera-label", text: "Gripper cam (joint Wrist)")
    end

    test "renders nothing about the driver's options", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> refute_has("*", text: "/dev/video0")
      |> refute_has("*", text: "hunter2")
    end

    test "a robot with no cameras shows only the 3D view", %{conn: conn} do
      conn
      |> visit("/robot")
      |> refute_has("[role=tablist]")
      |> assert_has(".bb-visualisation")
    end
  end

  describe "with no camera package installed" do
    setup do
      Application.put_env(:bb_liveview, :camera, BB.LiveView.Camera.BBCamera)
      :ok
    end

    test "the dashboard hides camera tabs without a camera package", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> refute_has("[role=tablist]")
      |> assert_has(".bb-visualisation")
    end

    test "a dashboard with no cameras is otherwise unchanged", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-widget", count: 6)
      |> assert_has(".bb-widget-title", text: "Safety")
    end
  end

  describe "the visual area tabs" do
    test "start on the 3D view, with no camera asked for anything", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[role=tab][aria-selected=true]", text: "3D view")
      |> assert_has("#bb-view-panel-visualisation .bb-visualisation")
      |> refute_has("[data-role=camera]")
      |> refute_has("[data-role=camera-preview]")

      assert SyntheticCamera.consumer_count(:eye) == 0
    end

    test "swap which one is on screen", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[role=tab][aria-selected=true]", text: "Cameras")
      |> assert_has("[data-role=camera]")
      |> refute_has("#bb-view-panel-visualisation .bb-visualisation")
      |> click_button("[data-role=view-tab][data-tab=visualisation]", "3D view")
      |> assert_has("#bb-view-panel-visualisation .bb-visualisation")
      |> refute_has("[data-role=camera]")
    end

    test "leave the always-on widgets alone", %{conn: conn} do
      session = open_cameras(conn, "/camera_robot")

      Enum.each(
        ["Safety", "Commands", "Joint Control", "Event Stream", "Parameters"],
        fn widget ->
          assert_has(session, ".bb-widget-title", text: widget)
        end
      )
    end

    test "are described for a screen reader", %{conn: conn} do
      conn
      |> visit("/camera_robot")
      |> assert_has("[role=tablist]")
      |> assert_has("#bb-view-tab-cameras[role=tab][aria-controls=bb-view-panel-cameras]")
      |> assert_has("#bb-view-panel-cameras[role=tabpanel][aria-labelledby=bb-view-tab-cameras]")
    end

    test "are all reachable from the keyboard", %{conn: conn} do
      # No roving tabindex: without arrow-key handlers it would take the
      # inactive tab out of the tab order and leave it reachable by nothing.
      conn
      |> visit("/camera_robot")
      |> refute_has("[role=tab][tabindex]")
    end
  end

  describe "leaving a camera behind" do
    test "drops the preview, and doesn't start it again on the way back", %{conn: conn} do
      session =
        conn
        |> open_cameras("/camera_robot")
        |> click_button("[data-role=camera-toggle]", "Start capturing")
        |> assert_has("[data-role=camera-preview]")
        |> click_button("[data-role=view-tab][data-tab=visualisation]", "3D view")
        |> click_button("[data-role=view-tab][data-tab=cameras]", "Cameras")

      # Coming back to the tab must not reopen the connection: that would
      # restart a capture the viewer only asked for once, and left.
      session
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-toggle]", text: "Start capturing")
    end

    test "keeps a pause, which is a decision rather than an accident", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Start capturing")
      |> click_button("[data-role=camera-toggle]", "Pause")
      |> click_button("[data-role=view-tab][data-tab=visualisation]", "3D view")
      |> click_button("[data-role=view-tab][data-tab=cameras]", "Cameras")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
      |> assert_has("[data-role=camera-toggle]", text: "Resume")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "shows a camera that is still capturing when you return", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-preview]")
      |> click_button("[data-role=view-tab][data-tab=visualisation]", "3D view")
      |> click_button("[data-role=view-tab][data-tab=cameras]", "Cameras")
      |> assert_has("[data-role=camera-preview]")
    end
  end

  describe "the camera selector" do
    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam}
         ]
    test "shows one camera at a time", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera]", count: 1)
      |> assert_has("[data-camera=eye]")
      |> refute_has("[data-camera=gripper_cam]")
    end

    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam}
         ]
    test "swapping camera takes the previous preview off screen", %{conn: conn} do
      session =
        conn
        |> open_cameras("/camera_robot")
        |> click_button("[data-role=camera-toggle]", "Start capturing")
        |> assert_has("[data-camera=eye] [data-role=camera-preview]")
        |> select("Camera", option: "Gripper cam")

      session
      |> refute_has("[data-camera=eye]")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-toggle]",
        text: "Start capturing"
      )
      |> select("Camera", option: "Eye")
      |> assert_has("[data-camera=eye] [data-role=camera-toggle]", text: "Start capturing")
      |> refute_has("[data-role=camera-preview]")
    end

    @tag cameras: [
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam}
         ]
    test "the grid shows them all, and one at a time again afterwards", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-view-toggle]", "Compare all")
      |> assert_has("[data-role=camera]", count: 2)
      |> click_button("[data-role=camera-view-toggle]", "Show one")
      |> assert_has("[data-role=camera]", count: 1)
    end
  end

  describe "an idle camera" do
    test "is not previewed, and nothing is asked of it", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
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
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Start capturing")
      |> assert_has("[data-role=camera-preview][src^='/camera_robot/__bb_camera__/eye/mjpeg']")
      |> assert_has("[data-role=camera-toggle]", text: "Pause")
    end

    test "stays shown while the camera is still catching up", %{conn: conn} do
      # The `<img>` is what creates the demand, so it has to appear before the
      # camera reports capturing — otherwise nothing would ever start.
      conn
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Start capturing")
      |> assert_has("[data-camera=eye][data-status=running] [data-role=camera-preview]")
    end
  end

  describe "a camera that is already capturing" do
    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "previews without being asked", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-toggle]", text: "Pause")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "stays hidden if the viewer paused it", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-toggle]", "Pause")
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
    end
  end

  describe "when the robot says a camera started capturing" do
    test "it appears, without anyone on this page asking", %{conn: conn} do
      session = open_cameras(conn, "/camera_robot")

      refute_has(session, "[data-role=camera-preview]")

      session
      |> capture_started(:eye)
      |> assert_has("[data-role=camera-preview]")
    end

    test "a paused camera stays paused", %{conn: conn} do
      session =
        conn
        |> open_cameras("/camera_robot")
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
        |> open_cameras("/camera_robot")
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
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-view-toggle]", "Compare all")
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
    test "carry the hook that cancels the stream when they go", %{conn: conn} do
      # Removing the element is not enough: a multipart response never ends on
      # its own and the browser keeps reading a detached one. Without this
      # hook, Pause leaves the webcam light on.
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-preview][phx-hook=CameraPreview]")
      |> assert_has("#bb-camera-preview-eye[data-role=camera-preview]")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "point at the camera route under the dashboard's own mount path", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-preview][src^='/camera_robot/__bb_camera__/eye/mjpeg']")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :declared}]
    test "an offline camera is shown as offline, not hidden", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
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
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-placeholder]", text: "can't be previewed as MJPEG")
      |> refute_has("[data-role=camera-preview]")
      |> refute_has("[data-role=camera-toggle]")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, stream: nil}]
    test "a camera that hasn't reported a format yet waits rather than failing", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
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
      |> open_cameras("/camera_robot")
      |> click_button("[data-role=camera-view-toggle]", "Compare all")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-preview][src$='?g=0']")
      |> click_button("[data-camera=eye] [data-role=camera-toggle]", "Pause")
      |> click_button("[data-camera=eye] [data-role=camera-toggle]", "Resume")
      |> assert_has("[data-camera=gripper_cam] [data-role=camera-preview][src$='?g=0']")
      |> refute_has("[data-camera=eye] [data-role=camera-preview][src$='?g=0']")
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :capturing}]
    test "pausing drops the image, which is what closes the connection", %{conn: conn} do
      conn
      |> open_cameras("/camera_robot")
      |> assert_has("[data-role=camera-preview]")
      |> click_button("[data-role=camera-toggle]", "Pause")
      |> refute_has("[data-role=camera-preview]")
      |> assert_has("[data-role=camera-placeholder]", text: "Paused")
      |> click_button("[data-role=camera-toggle]", "Resume")
      |> assert_has("[data-role=camera-preview]")
    end
  end

  # Every camera assertion needs the Cameras tab open: the 3D view is the
  # default, and the camera panel renders nothing — no `<img>`, no request —
  # until it is the chosen one.
  defp open_cameras(conn, path) do
    conn
    |> visit(path)
    |> click_button("[data-role=view-tab][data-tab=cameras]", "Cameras")
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
