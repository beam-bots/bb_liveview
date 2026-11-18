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

  ## Opening the dashboard does not switch a camera on

  Requesting a preview is what creates demand, and demand is what starts the
  capture. So a camera that is merely *running* — its driver alive, nothing
  capturing — renders no `<img>` and makes no request until someone asks for
  one. Opening a dashboard should not spin up every camera on a robot, wake a
  laptop's webcam light, or start paying for frames nobody is looking at.

  A camera that is **already capturing** previews straight away. Watching it
  still costs a connection, a consumer and the bandwidth to carry the frames —
  what it doesn't cost is starting a capture that wasn't running. That includes
  a camera that starts capturing later for someone else's reasons: the preview
  appears when the robot says so.

  What the viewer decides outranks both. Starting a preview shows it even
  before the camera reports that it has caught up, and pausing one keeps it
  hidden even while the camera carries on capturing for others. That choice
  survives every routine refresh of the camera list, and is forgotten only when
  the component is pointed at a different robot.
  """
  use Phoenix.LiveComponent

  alias BB.LiveView.Camera

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, cameras: [], choices: %{}, generations: %{}, base_path: "/")}
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
        # A different robot's cameras are different cameras, whatever they are
        # called, so neither the viewer's choices nor their cache-busting
        # counters carry over.
        assign(socket,
          cameras: Camera.discover(robot_module),
          choices: %{},
          generations: %{}
        )
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl Phoenix.LiveComponent
  def handle_event("toggle_preview", %{"camera" => name}, socket) do
    choice = if showing?(socket.assigns, name), do: :off, else: :on

    # Only the toggled camera's URL moves. A counter shared across cameras
    # would change every `src` on the page, and every other browser connection
    # would be torn down and rebuilt to resume one of them.
    generations = Map.update(socket.assigns.generations, name, 1, &(&1 + 1))

    {:noreply,
     socket
     |> assign(:choices, Map.put(socket.assigns.choices, name, choice))
     |> assign(:generations, generations)}
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
              :if={previewing?(camera, @choices)}
              class="bb-camera-image"
              data-role="camera-preview"
              src={preview_src(@base_path, camera, @generations)}
              alt={"Live preview of #{Camera.label(camera)}"}
            />
            <p
              :if={!previewing?(camera, @choices)}
              class="bb-camera-placeholder"
              data-role="camera-placeholder"
            >
              {placeholder_message(camera, @choices)}
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
              {toggle_label(camera, @choices)}
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

  defp choice(camera, choices), do: Map.get(choices, Atom.to_string(camera.name))

  defp placeholder_message(%{status: :declared}, _choices),
    do: "Offline — declared in the robot but not running"

  defp placeholder_message(%{previewable?: false, stream: nil}, _choices),
    do: "Waiting for the driver to report a stream format"

  defp placeholder_message(%{previewable?: false, stream: stream}, _choices),
    do: "#{inspect(stream.format)} can't be previewed as MJPEG"

  defp placeholder_message(camera, choices) do
    if choice(camera, choices) == :off do
      "Paused"
    else
      "Idle — nothing is capturing. Start a preview to begin."
    end
  end

  # A per-camera counter changes that camera's URL when its preview resumes, so
  # the browser opens a fresh request instead of reviving a cached one.
  defp preview_src(base_path, camera, generations) do
    generation = Map.get(generations, Atom.to_string(camera.name), 0)
    "#{Camera.stream_path(base_path, camera)}?g=#{generation}"
  end

  # Watching is free when something else is already paying for the frames, and
  # costs a capture when nothing is. The viewer's own choice beats both.
  defp previewing?(camera, choices) do
    camera.previewable? and camera.status != :declared and
      case choice(camera, choices) do
        :off -> false
        :on -> true
        nil -> camera.status == :capturing
      end
  end

  defp showing?(assigns, name) do
    assigns.cameras
    |> Enum.find(&(Atom.to_string(&1.name) == name))
    |> case do
      nil -> false
      camera -> previewing?(camera, assigns.choices)
    end
  end

  defp toggle_label(camera, choices) do
    cond do
      previewing?(camera, choices) -> "Pause"
      choice(camera, choices) == :off -> "Resume"
      true -> "Start capturing"
    end
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
