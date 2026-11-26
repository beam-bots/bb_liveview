# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Camera.BBCameraTest do
  # The robot and `bb_camera_webrtc`'s pipeline registry are global.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [build_conn: 0, get: 2]

  import Phoenix.LiveViewTest,
    only: [assert_push_event: 4, element: 2, has_element?: 2, live: 2, render_click: 1]

  alias BB.LiveView.Camera
  alias BB.LiveView.Camera.BBCamera
  alias BB.LiveView.WebRTCRobot

  # An upper bound on events that must happen — a pipeline starting, an
  # encoder producing its first keyframe — not a guess at how long they take.
  @within 15_000

  @endpoint BB.LiveView.TestEndpoint

  setup do
    # A pipeline outlives its last viewer briefly. Joining one on its way out
    # ends the stream at once, which the dashboard answers by watching again,
    # but a test wants to start from nothing.
    await_no_pipeline()
    start_supervised!(WebRTCRobot)
    assert Camera.implementation() == BBCamera
    :ok
  end

  test "both packages are available" do
    assert BBCamera.available?()
    assert BBCamera.webrtc_available?()
  end

  test "discovers the robot's camera as previewable" do
    assert [%{name: :eye, previewable?: true, stream: %{format: {:raw, :I420}}}] =
             Camera.discover(WebRTCRobot)
  end

  test "finds no cameras on a robot that isn't a `use BB` module" do
    assert Camera.discover(BB.LiveView.TestRobot) == []
  end

  test "the camera's offer reaches the caller as JSON-shaped signalling" do
    {:ok, watch} = Camera.watch(WebRTCRobot, :eye)

    assert {:signal, %{"type" => "sdp_offer", "data" => %{"sdp" => _}}} = next_event(watch)
  end

  test "unwatching stops the camera's pipeline, and the stream says nothing more" do
    {:ok, watch} = Camera.watch(WebRTCRobot, :eye)
    assert {:signal, _offer} = next_event(watch)
    monitor = Process.monitor(pipeline())

    assert :ok = Camera.unwatch(watch)

    assert_receive {:DOWN, ^monitor, :process, _pipeline, _reason}, @within
    refute :ended in events_received(watch)
  end

  test "the viewer exiting stops the camera's pipeline" do
    test = self()

    viewer =
      spawn(fn ->
        {:ok, watch} = Camera.watch(WebRTCRobot, :eye)
        assert {:signal, _offer} = next_event(watch)
        send(test, :streaming)

        receive do
          :never_sent -> :ok
        end
      end)

    assert_receive :streaming, @within
    monitor = Process.monitor(pipeline())

    Process.exit(viewer, :kill)

    assert_receive {:DOWN, ^monitor, :process, _pipeline, _reason}, @within
  end

  test "the camera going away ends the stream" do
    {:ok, watch} = Camera.watch(WebRTCRobot, :eye)
    assert {:signal, _offer} = next_event(watch)

    stop_supervised!(WebRTCRobot)

    assert next_end(watch) == :ended
  end

  test "a watch that can't start is an error, not a crash" do
    assert {:error, _reason} = Camera.watch(WebRTCRobot, :eye, ice_servers: :not_a_list)
  end

  test "the dashboard plays the camera: its offer is pushed to the player" do
    {:ok, view, _html} = live(build_conn(), "/web_rtc_robot")
    view |> element("[data-role=view-tab][data-tab=cameras]") |> render_click()
    view |> element("[data-role=camera-toggle]") |> render_click()

    assert has_element?(view, "video#bb-camera-video-eye-1[phx-hook=CameraPlayer]")

    assert_push_event(
      view,
      "webrtc_signaling-bb-camera-video-eye-1",
      %{"type" => "sdp_offer"},
      @within
    )
  end

  # Every event already in the mailbox for `watch`, without waiting for more.
  defp events_received(watch) do
    receive do
      message ->
        case Camera.stream_event(watch, message) do
          nil -> events_received(watch)
          event -> [event | events_received(watch)]
        end
    after
      0 -> []
    end
  end

  # The stream's end, passing over the signalling still on its way.
  defp next_end(watch) do
    case next_event(watch) do
      {:signal, _message} -> next_end(watch)
      :ended -> :ended
    end
  end

  # The next message from `watch`'s stream, whatever its shape.
  defp next_event(watch) do
    receive do
      message ->
        case Camera.stream_event(watch, message) do
          nil -> next_event(watch)
          event -> event
        end
    after
      @within -> flunk("the stream sent nothing")
    end
  end

  defp await_no_pipeline do
    case Registry.lookup(BB.Camera.WebRTC.Registry, {WebRTCRobot, :eye}) do
      [] ->
        :ok

      [{pipeline, _value}] ->
        monitor = Process.monitor(pipeline)
        assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, @within
    end
  end

  defp pipeline do
    [{pipeline, _value}] = Registry.lookup(BB.Camera.WebRTC.Registry, {WebRTCRobot, :eye})
    pipeline
  end
end
