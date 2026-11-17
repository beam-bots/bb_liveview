# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Cameras do
  @moduledoc """
  LiveComponent listing the robot's cameras and previewing them.

  Cameras are discovered from the robot's DSL, so they appear whether or not
  the robot is running: a camera that is declared but offline is shown as
  offline rather than omitted, which is the difference between "this robot has
  no camera" and "this robot's camera isn't working".

  No pixels travel through the LiveView socket. Each preview is an `<img>`
  pointing at `BB.LiveView.Plugs.CameraStream`, mounted in the same scope as
  the dashboard, so the browser fetches the MJPEG stream over an ordinary HTTP
  connection through the host's own pipeline. Pausing a preview removes the
  element, which closes that connection, which drops the consumer — and the
  camera stops capturing once the last one goes.
  """
  use Phoenix.LiveComponent

  alias BB.LiveView.Camera

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, cameras: [], paused: MapSet.new(), generation: 0, base_path: "/")}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: :cameras_changed}, socket) do
    {:ok, assign(socket, :cameras, Camera.discover(socket.assigns.robot_module))}
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] == robot_module do
        socket
      else
        assign(socket, cameras: Camera.discover(robot_module))
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl Phoenix.LiveComponent
  def handle_event("toggle_preview", %{"camera" => name}, socket) do
    paused = socket.assigns.paused

    paused =
      if MapSet.member?(paused, name),
        do: MapSet.delete(paused, name),
        else: MapSet.put(paused, name)

    {:noreply,
     socket
     |> assign(:paused, paused)
     |> assign(:generation, socket.assigns.generation + 1)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :cameras, Camera.discover(socket.assigns.robot_module))}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-cameras" data-role="cameras">
      <div :if={@cameras == []} class="bb-empty-state" data-role="cameras-empty">
        <p class="bb-empty-state-message">{empty_message()}</p>
      </div>

      <div :if={@cameras != []} class="bb-camera-grid">
        <div
          :for={camera <- @cameras}
          class="bb-camera"
          data-role="camera"
          data-camera={camera.name}
          data-status={camera.status}
        >
          <div class="bb-camera-header">
            <span class="bb-camera-label">{Camera.label(camera)}</span>
            <span class={"bb-camera-status #{camera.status}"}>{status_text(camera.status)}</span>
          </div>

          <div class="bb-camera-view">
            <img
              :if={previewing?(camera, @paused)}
              class="bb-camera-image"
              data-role="camera-preview"
              src={preview_src(@base_path, camera, @generation)}
              alt={"Live preview of #{Camera.label(camera)}"}
            />
            <p :if={!previewing?(camera, @paused)} class="bb-camera-placeholder" data-role="camera-placeholder">
              {placeholder_message(camera, @paused)}
            </p>
          </div>

          <div class="bb-camera-footer">
            <span class="bb-camera-stream">{stream_text(camera.stream)}</span>
            <button
              :if={camera.previewable? and camera.status != :declared}
              type="button"
              class="bb-camera-toggle"
              data-role="camera-toggle"
              phx-click="toggle_preview"
              phx-target={@myself}
              phx-value-camera={camera.name}
            >
              {if paused?(camera, @paused), do: "Resume", else: "Pause"}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp empty_message do
    if Camera.available?() do
      "This robot declares no cameras"
    else
      "No camera package installed — add bb_camera and a driver to preview cameras here"
    end
  end

  defp paused?(camera, paused), do: MapSet.member?(paused, Atom.to_string(camera.name))

  defp placeholder_message(%{status: :declared}, _paused),
    do: "Offline — declared in the robot but not running"

  defp placeholder_message(%{previewable?: false, stream: nil}, _paused),
    do: "Waiting for the driver to report a stream format"

  defp placeholder_message(%{previewable?: false, stream: stream}, _paused),
    do: "#{inspect(stream.format)} can't be previewed as MJPEG"

  defp placeholder_message(_camera, _paused), do: "Paused"

  # The generation counter changes the URL when a preview resumes, so the
  # browser opens a fresh request instead of reviving a cached one.
  defp preview_src(base_path, camera, generation) do
    "#{Camera.stream_path(base_path, camera)}?g=#{generation}"
  end

  defp previewing?(camera, paused) do
    camera.previewable? and camera.status != :declared and not paused?(camera, paused)
  end

  defp status_text(:capturing), do: "Capturing"
  defp status_text(:running), do: "Idle"
  defp status_text(:declared), do: "Offline"

  defp stream_text(nil), do: "Format unknown"

  defp stream_text(%{format: format, width: width, height: height, frame_rate: nil}),
    do: "#{inspect(format)} #{width}×#{height}"

  defp stream_text(%{format: format, width: width, height: height, frame_rate: rate}),
    do: "#{inspect(format)} #{width}×#{height} @ #{rate} fps"
end
