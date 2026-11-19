# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.CameraTest do
  use BB.LiveView.CameraCase

  describe "discover/1" do
    test "finds the robot's cameras" do
      assert [camera] = Camera.discover(CameraRobot)
      assert camera.name == :eye
      assert camera.path == [:sensor, :head, :eye]
      assert camera.attached_to == {:link, :head}
      assert camera.status == :running
      assert camera.previewable?
    end

    test "reports nothing a driver wasn't asked for" do
      [camera] = Camera.discover(CameraRobot)

      refute Map.has_key?(camera, :options)
      refute Map.has_key?(camera, :metadata)
      refute camera |> inspect() |> String.contains?("/dev/video0")
      refute camera |> inspect() |> String.contains?("hunter2")
    end

    test "summarises the stream without the driver's metadata" do
      [camera] = Camera.discover(CameraRobot)

      assert camera.stream == %{format: :jpeg, width: 160, height: 120, frame_rate: 10.0}
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye}]
    test "ignores robots it has no cameras for" do
      assert Camera.discover(BB.LiveView.TestRobot) == []
    end

    test "answers nothing for things that aren't robots" do
      assert Camera.discover(NotARobot) == []
      assert Camera.discover("TestRobot") == []
      assert Camera.discover(nil) == []
    end
  end

  describe "with no camera package installed" do
    setup do
      Application.put_env(:bb_liveview, :camera, BB.LiveView.Camera.BBCamera)
      :ok
    end

    test "nothing is available" do
      refute Camera.available?()
    end

    test "every robot has no cameras" do
      assert Camera.discover(CameraRobot) == []
    end

    test "opening a session says why rather than crashing" do
      assert {:error, :no_camera_implementation} = Camera.open(CameraRobot, :eye)
    end
  end

  describe "fetch/2" do
    test "resolves a declared camera by name" do
      assert {:ok, %{name: :eye}} = Camera.fetch(CameraRobot, "eye")
    end

    test "misses on an unknown name without inventing an atom" do
      name = "a_camera_that_has_never_existed"

      assert :error = Camera.fetch(CameraRobot, name)

      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "misses on anything that isn't a string" do
      assert :error = Camera.fetch(CameraRobot, :eye)
      assert :error = Camera.fetch(CameraRobot, nil)
    end
  end

  describe "label/1" do
    test "names the camera and where it hangs" do
      [camera] = Camera.discover(CameraRobot)

      assert Camera.label(camera) == "Eye (link Head)"
    end

    test "names a robot-level camera on its own" do
      assert Camera.label(%{name: :front_camera, attached_to: :robot}) == "Front camera"
    end
  end

  describe "stream_path/2" do
    test "hangs the stream off wherever the dashboard is mounted" do
      assert Camera.stream_path("/robot", :eye) == "/robot/__bb_camera__/eye/mjpeg"
      assert Camera.stream_path("/", :eye) == "/__bb_camera__/eye/mjpeg"
      assert Camera.stream_path("/admin/arm/", :eye) == "/admin/arm/__bb_camera__/eye/mjpeg"
    end
  end

  describe "demand" do
    test "a consumer that reads slowly skips frames instead of queueing them" do
      {:ok, session} = Camera.open(CameraRobot, :eye, format: :jpeg)

      Enum.each(1..5, fn _ -> SyntheticCamera.capture(:eye) end)

      # Nothing was asked for, so nothing was delivered: the five frames
      # collapsed into one latest frame rather than five mailbox entries.
      refute_received {:synthetic_camera_frame, _ref, _result}

      assert {:ok, frame} = Camera.next(session, 1000)
      assert frame.sequence == 5

      Camera.close(session)
    end

    test "each frame is newer than the last, so a reader can't spin on repeats" do
      {:ok, session} = Camera.open(CameraRobot, :eye, format: :jpeg)

      SyntheticCamera.capture(:eye)
      assert {:ok, %{sequence: 1}} = Camera.next(session, 1000)

      # Nothing is capturing, so no frame can arrive: the session waits for one
      # that doesn't exist rather than handing back sequence 1 a second time.
      # That is what stops the MJPEG writer spinning on repeats.
      assert {:error, :timeout} = Camera.next(session, 100)

      SyntheticCamera.capture(:eye)
      assert {:ok, %{sequence: 2}} = Camera.next(session, 1000)

      Camera.close(session)
    end

    test "closing releases the consumer and stops the capture" do
      {:ok, session} = Camera.open(CameraRobot, :eye, format: :jpeg)
      assert_receive {:synthetic_camera, {:capture_started, :eye}}
      assert SyntheticCamera.consumer_count(:eye) == 1

      :ok = Camera.close(session)

      assert_receive {:synthetic_camera, {:consumer_released, :eye, :closed}}
      assert_receive {:synthetic_camera, {:capture_stopped, :eye}}
      assert SyntheticCamera.consumer_count(:eye) == 0
    end

    test "one capture is shared by several consumers" do
      {:ok, first} = Camera.open(CameraRobot, :eye, format: :jpeg)
      assert_receive {:synthetic_camera, {:capture_started, :eye}}

      {:ok, second} = Camera.open(CameraRobot, :eye, format: :jpeg)
      assert SyntheticCamera.consumer_count(:eye) == 2

      Camera.close(first)
      assert_receive {:synthetic_camera, {:consumer_released, :eye, :closed}}
      refute_received {:synthetic_camera, {:capture_stopped, :eye}}

      Camera.close(second)
      assert_receive {:synthetic_camera, {:capture_stopped, :eye}}
    end

    test "closing a session twice is harmless" do
      {:ok, session} = Camera.open(CameraRobot, :eye, format: :jpeg)

      assert :ok = Camera.close(session)
      assert :ok = Camera.close(session)
    end
  end

  describe "open/3" do
    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :declared}]
    test "refuses a camera that isn't running" do
      assert {:error, :not_running} = Camera.open(CameraRobot, :eye, format: :jpeg)
    end

    @tag cameras: [
           %{
             robot: BB.LiveView.CameraRobot,
             name: :depth,
             stream: %{format: {:raw, :rgb8}, width: 64, height: 48, frame_rate: nil}
           }
         ]
    test "refuses a format the browser can't render" do
      assert {:error, :unsupported_format} = Camera.open(CameraRobot, :depth, format: :jpeg)
    end

    test "refuses a camera the robot doesn't have" do
      assert {:error, :unknown_camera} = Camera.open(CameraRobot, :nonexistent, format: :jpeg)
    end
  end
end
