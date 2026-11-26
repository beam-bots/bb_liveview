# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Camera.BBCamera do
  @moduledoc """
  The default `BB.LiveView.Camera` implementation: the real `bb_camera`, and
  `bb_camera_webrtc` to stream it.

  Every call dispatches on a module held in a variable rather than written
  inline, and every entry point is guarded by an availability check. That is
  what makes both packages genuinely optional dependencies of this library:
  with them absent nothing here resolves a missing module, the compiler has no
  undefined call to warn about, and a dashboard for a robot with no cameras
  behaves exactly as it did before cameras existed.
  """

  @behaviour BB.LiveView.Camera

  @typedoc """
  A stream: what `BB.Camera.WebRTC.unwatch/3` needs, and the signalling
  channel this process is the browser's peer on.
  """
  @type watch :: %{robot: module, camera: atom, ref: reference, signaling: struct}

  @impl BB.LiveView.Camera
  def available? do
    Code.ensure_loaded?(camera())
  end

  # `bb_camera` reads cameras out of the robot's DSL, so anything that isn't a
  # `use BB` module — a hand-written stand-in, say — has none to find.
  @impl BB.LiveView.Camera
  def discover(robot_module) do
    if function_exported?(robot_module, :spark_dsl_config, 0) do
      camera().discover(robot_module)
    else
      []
    end
  end

  @impl BB.LiveView.Camera
  def signal(watch, message) do
    signaling().signal(watch.signaling, message)
  end

  @impl BB.LiveView.Camera
  def stream_event(%{signaling: %{pid: pid}}, {:membrane_webrtc_signaling, pid, message, _meta}),
    do: {:signal, message}

  def stream_event(%{ref: ref}, {BB.Camera.WebRTC, ref, :ended}), do: :ended
  def stream_event(%{ref: ref}, {:DOWN, ref, :process, _pid, _reason}), do: :ended
  def stream_event(_watch, _message), do: nil

  @impl BB.LiveView.Camera
  def stream_message?({:membrane_webrtc_signaling, _pid, _message, _meta}), do: true
  def stream_message?({BB.Camera.WebRTC, _ref, :ended}), do: true
  def stream_message?({:DOWN, _ref, :process, _pid, _reason}), do: true
  def stream_message?(_message), do: false

  @impl BB.LiveView.Camera
  def unwatch(watch) do
    web_rtc().unwatch(watch.robot, watch.camera, watch.ref)
  end

  # The signalling channel is started unlinked: it stops by itself once either
  # peer — this process or the WebRTC sink — has gone, and a link would turn a
  # sink crashing into the dashboard crashing. A watch that fails to start
  # leaves it with only this process as a peer, so it is closed here rather
  # than left until the dashboard goes.
  @impl BB.LiveView.Camera
  def watch(robot_module, camera_name, opts) do
    signaling = signaling().start()
    :ok = signaling().register_peer(signaling, message_format: :json_data)

    case web_rtc().watch(robot_module, camera_name, signaling, opts) do
      {:ok, ref} ->
        {:ok, %{robot: robot_module, camera: camera_name, ref: ref, signaling: signaling}}

      {:error, reason} ->
        signaling().close(signaling)
        {:error, reason}
    end
  end

  @impl BB.LiveView.Camera
  def webrtc_available? do
    Code.ensure_loaded?(web_rtc())
  end

  # Assembled at runtime rather than written as aliases. Spelling the modules
  # out would let the compiler resolve the calls and warn that `bb_camera` and
  # `bb_camera_webrtc` are undefined — which they are, here, and are allowed
  # to be: that is the whole point of an optional dependency. `available?/0`
  # and `webrtc_available?/0` decide whether these are safe to call.
  defp camera, do: Module.concat([:BB, :Camera])
  defp signaling, do: Module.concat([:Membrane, :WebRTC, :Signaling])
  defp web_rtc, do: Module.concat([:BB, :Camera, :WebRTC])
end
