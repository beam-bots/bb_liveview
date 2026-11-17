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

  describe "previews" do
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
           %{robot: BB.LiveView.CameraRobot, name: :eye},
           %{robot: BB.LiveView.CameraRobot, name: :gripper_cam}
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
end
