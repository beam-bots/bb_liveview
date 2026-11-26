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

      assert camera.stream == %{format: {:raw, :I420}, width: 160, height: 120, frame_rate: 10.0}
    end

    @tag cameras: [
           %{
             robot: BB.LiveView.CameraRobot,
             name: :depth,
             stream: %{format: {:raw, :Y16}, width: 64, height: 48, frame_rate: nil}
           }
         ]
    test "only a raw I420 stream is previewable" do
      assert [%{previewable?: false}] = Camera.discover(CameraRobot)
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, stream: nil}]
    test "a camera that hasn't reported a format isn't previewable yet" do
      assert [%{previewable?: false, stream: nil}] = Camera.discover(CameraRobot)
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
    @describetag available?: false

    test "nothing is available" do
      refute Camera.available?()
      refute Camera.webrtc_available?()
    end

    test "every robot has no cameras" do
      assert Camera.discover(CameraRobot) == []
    end

    test "watching says why rather than crashing" do
      assert {:error, :no_webrtc} = Camera.watch(CameraRobot, :eye)
    end
  end

  describe "without bb_camera_webrtc" do
    @describetag webrtc?: false

    test "cameras are listed but can't be previewed" do
      assert Camera.available?()
      refute Camera.webrtc_available?()
      assert [%{name: :eye, previewable?: false}] = Camera.discover(CameraRobot)
    end

    test "watching says why rather than crashing" do
      assert {:error, :no_webrtc} = Camera.watch(CameraRobot, :eye)
      refute_received {:synthetic_camera, {:watching, _camera, _stream, _opts}}
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

  describe "watch/3" do
    test "streams on behalf of the caller, passing on its options" do
      ice_servers = [%{urls: "stun:stun.example.com"}]

      assert {:ok, watch} = Camera.watch(CameraRobot, :eye, ice_servers: ice_servers)
      assert_received {:synthetic_camera, {:watching, :eye, ^watch, [ice_servers: ^ice_servers]}}
      assert watch.viewer == self()
    end

    test "the stream's signalling arrives at the caller, and is recognised" do
      {:ok, watch} = Camera.watch(CameraRobot, :eye)
      offer = %{"type" => "sdp_offer", "data" => %{"type" => "offer", "sdp" => "v=0"}}

      SyntheticCamera.to_browser(watch, offer)

      assert_received {SyntheticCamera, _ref, _event} = message
      assert Camera.stream_message?(message)
      assert Camera.stream_event(watch, message) == {:signal, offer}
    end

    test "the caller is told when the stream ends" do
      {:ok, watch} = Camera.watch(CameraRobot, :eye)

      SyntheticCamera.end_stream(watch)

      assert_received {SyntheticCamera, _ref, _event} = message
      assert Camera.stream_event(watch, message) == :ended
    end

    test "one stream's messages mean nothing to another" do
      {:ok, first} = Camera.watch(CameraRobot, :eye)
      {:ok, second} = Camera.watch(CameraRobot, :eye)

      SyntheticCamera.end_stream(first)

      assert_received {SyntheticCamera, _ref, _event} = message
      assert Camera.stream_event(first, message) == :ended
      assert Camera.stream_event(second, message) == nil
    end

    test "messages that aren't from a stream aren't claimed" do
      refute Camera.stream_message?({:DOWN, make_ref(), :process, self(), :normal})
      refute Camera.stream_message?(:load_robot_data)
    end

    test "unwatch/1 stops the stream" do
      {:ok, watch} = Camera.watch(CameraRobot, :eye)

      assert :ok = Camera.unwatch(watch)

      assert_received {:synthetic_camera, {:unwatched, :eye, ^watch}}
    end

    @tag cameras: [%{robot: BB.LiveView.CameraRobot, name: :eye, status: :declared}]
    test "a camera that can't be watched is an error, not a crash" do
      assert {:error, _reason} = Camera.watch(CameraRobot, :eye)
    end
  end

  describe "signal/2" do
    setup do
      {:ok, watch} = Camera.watch(CameraRobot, :eye)
      {:ok, watch: watch}
    end

    test "passes the browser's answer and candidates to the stream", %{watch: watch} do
      answer = %{"type" => "sdp_answer", "data" => %{"type" => "answer", "sdp" => "v=0"}}
      candidate = %{"type" => "ice_candidate", "data" => %{"candidate" => "candidate:1 1 UDP"}}

      Camera.signal(watch, Map.merge(answer, %{"camera" => "eye", "session" => 1}))
      Camera.signal(watch, candidate)

      assert_received {:synthetic_camera, {:from_browser, :eye, ^answer}}
      assert_received {:synthetic_camera, {:from_browser, :eye, ^candidate}}
    end

    test "drops the end-of-candidates marker and anything that isn't signalling", %{
      watch: watch
    } do
      Camera.signal(watch, %{"type" => "ice_candidate", "data" => nil})
      Camera.signal(watch, %{"type" => "ice_candidate", "data" => %{"candidate" => ""}})
      Camera.signal(watch, %{"type" => "sdp_offer", "data" => %{"sdp" => "v=0"}})
      Camera.signal(watch, %{"hello" => "world"})

      refute_received {:synthetic_camera, {:from_browser, :eye, _message}}
    end
  end
end
