# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Camera.BBCamera do
  @moduledoc """
  The default `BB.LiveView.Camera` implementation: the real `bb_camera`.

  Every call dispatches on a module held in a variable rather than written
  inline, and every entry point is guarded by `available?/0`. That is what
  makes `bb_camera` a genuinely optional dependency of this library: with the
  package absent nothing here resolves a missing module, the compiler has no
  undefined call to warn about, and a dashboard for a robot with no cameras
  behaves exactly as it did before cameras existed.
  """

  @behaviour BB.LiveView.Camera

  @impl BB.LiveView.Camera
  def available? do
    Code.ensure_loaded?(camera())
  end

  @impl BB.LiveView.Camera
  def close(session) do
    media().close(session)
  end

  @impl BB.LiveView.Camera
  def discover(robot_module) do
    camera().discover(robot_module)
  end

  @impl BB.LiveView.Camera
  def next(session, timeout) do
    media().next(session, timeout)
  end

  @impl BB.LiveView.Camera
  def open(robot_module, camera_name, opts) do
    media().open(robot_module, camera_name, opts)
  end

  # Assembled at runtime rather than written as an alias. Spelling the module
  # out would let the compiler resolve the call and warn that `bb_camera` is
  # undefined — which it is, here, and is allowed to be: that is the whole
  # point of an optional dependency. `available?/0` is what decides whether
  # these are safe to call.
  defp camera, do: Module.concat([:BB, :Camera])
  defp media, do: Module.concat([:BB, :Camera, :Media])
end
