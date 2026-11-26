# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Cameras do
  @moduledoc """
  LiveComponent listing the robot's cameras and previewing them over WebRTC.

  Cameras are discovered from the robot's DSL, so they appear whether or not
  the robot is running: a camera that is declared but offline is shown as
  offline rather than omitted, which is the difference between "this robot has
  no camera" and "this robot's camera isn't working".

  ## How a preview plays

  Each preview is a `<video>` playing a `BB.LiveView.Camera.watch/3` stream.
  The video travels from the robot to the browser over WebRTC; the LiveView
  socket carries only the signalling that sets the connection up. This
  component runs in the dashboard's process, so the dashboard is the process
  that watches. It forwards every message `BB.LiveView.Camera.stream_message?/1`
  claims here as `{:stream_message, message}`, and the watch it belongs to
  says what it means: signalling is pushed to the camera's `CameraPlayer` hook
  as `webrtc_signaling-<video id>`, and an end is handled as below.

  The hook's replies come back as `webrtc_signaling` events, tagged with the
  camera and session they belong to.

  ## Sessions

  Every watch is a session, numbered per camera, and the session is part of
  the `<video>` element's id. Starting a new one therefore replaces the
  element, which destroys the old hook — closing its peer connection — and
  mounts a new one for the new stream. Signalling addressed to an old session
  has nowhere to go in the browser, and replies from one are dropped here.

  ## When a stream ends

  The camera stopped or restarted, the browser's connection failed, or the
  pipeline went down: the stream ends, and a camera that is still on screen is
  watched again straight away with a new session. A stream that ended before
  it said anything — a camera that can't be streamed right now — is retried
  a couple of seconds later instead, so a camera that keeps failing isn't
  restarted in a tight loop. So is a watch that fails to start. The retry is
  an ordinary `send_update` of `{:retry, camera, session}`, which a test can
  send itself.

  ## Opening the dashboard does not switch a camera on

  Watching is what creates demand, and demand is what starts the capture. So
  a camera that is merely *running* — its driver alive, nothing capturing — is
  not watched until someone asks for it. Opening a dashboard should not spin
  up every camera on a robot, wake a laptop's webcam light, or start paying
  for frames nobody is looking at.

  A camera that is **already capturing** previews straight away. Watching it
  still costs an encoder branch and the bandwidth — what it doesn't cost is
  starting a capture that wasn't running. That includes a camera that starts
  capturing later for someone else's reasons: the preview appears when the
  robot says so.

  ## One camera at a time

  The tab shows a single camera, chosen from a selector, because each preview
  is a live stream and a robot can have several. A grid view is there for
  comparing them, and costs exactly what it looks like it costs.

  Anything hidden — by switching tab, by choosing another camera, by leaving
  the grid — stops being watched. The capture itself is not necessarily
  stopped: other viewers may be watching, and that is the camera's decision,
  not this component's.

  A preview that was started and then hidden does not come back by itself,
  because coming back would silently restart a capture nobody asked for again.
  A camera that is *capturing* when you return shows, as it always does.

  What the viewer decides outranks both. Starting a preview shows it even
  before the camera reports that it has caught up, and pausing one keeps it
  hidden even while the camera carries on capturing for others. That choice
  survives every routine refresh of the camera list, and is forgotten only when
  the component is pointed at a different robot.
  """
  use Phoenix.LiveComponent

  alias BB.LiveView.Camera

  @retry_ms 2_000

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       cameras: [],
       choices: %{},
       ice_servers: [],
       selected: nil,
       sessions: %{},
       view: :single,
       visible: true,
       watches: %{},
       webrtc?: false
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: :cameras_changed}, socket) do
    {:ok, socket |> discover(socket.assigns.robot_module) |> settle()}
  end

  def update(%{event: {:stream_message, message}}, socket) do
    {:ok, handle_stream_event(socket, find_stream_event(socket, message))}
  end

  def update(%{event: {:retry, name, session}}, socket) do
    if Map.get(socket.assigns.watches, name) == {:retrying, session} do
      {:ok, socket |> drop_watch(name) |> settle()}
    else
      {:ok, socket}
    end
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] == robot_module do
        socket
      else
        # A different robot's cameras are different cameras, whatever they are
        # called, so neither the viewer's choices nor their streams carry over.
        socket
        |> stop_watches()
        |> assign(choices: %{}, selected: nil)
        |> discover(robot_module)
      end

    {:ok, socket |> assign(assigns) |> settle()}
  end

  def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> settle()}

  @impl Phoenix.LiveComponent
  def handle_event("toggle_preview", %{"camera" => name}, socket) do
    choice = if showing?(socket.assigns, name), do: :off, else: :on

    {:noreply,
     socket
     |> assign(:choices, Map.put(socket.assigns.choices, name, choice))
     |> settle()}
  end

  def handle_event("select_camera", %{"camera" => name}, socket) do
    {:noreply, socket |> assign(:selected, resolve(socket, name)) |> settle()}
  end

  def handle_event("toggle_view", _params, socket) do
    view = if socket.assigns.view == :grid, do: :single, else: :grid

    {:noreply, socket |> assign(:view, view) |> settle()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> discover(socket.assigns.robot_module) |> settle()}
  end

  def handle_event(
        "webrtc_signaling",
        %{"camera" => name, "session" => session} = message,
        socket
      ) do
    case Map.get(socket.assigns.watches, name) do
      %{session: ^session, watch: watch} -> Camera.signal(watch, message)
      _stale_or_unwatched -> :ok
    end

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-cameras" data-role="cameras">
      <div :if={@cameras == []} class="bb-empty-state" data-role="cameras-empty">
        <p class="bb-empty-state-message">{empty_message()}</p>
      </div>

      <div :if={@cameras != []}>
        <div class="bb-camera-controls">
          <form
            :if={@view == :single}
            id="bb-camera-select-form"
            phx-change="select_camera"
            phx-target={@myself}
          >
            <label class="bb-camera-select-label" for="bb-camera-select">Camera</label>
            <select id="bb-camera-select" name="camera" class="bb-camera-select">
              <option :for={camera <- @cameras} value={camera.name} selected={shown?(camera, @selected)}>
                {Camera.label(camera)}
              </option>
            </select>
          </form>

          <span :if={@view == :grid} class="bb-camera-select-label">
            All {length(@cameras)} cameras
          </span>

          <button
            type="button"
            class="bb-camera-view-toggle"
            data-role="camera-view-toggle"
            aria-pressed={to_string(@view == :grid)}
            phx-click="toggle_view"
            phx-target={@myself}
          >
            {if @view == :grid, do: "Show one", else: "Compare all"}
          </button>
        </div>

        <div class={["bb-camera-grid", @view == :grid && "bb-camera-grid-compare"]}>
          <div
            :for={camera <- visible_cameras(assigns)}
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
              <%= case watch_session(camera, @watches) do %>
                <% nil -> %>
                  <p class="bb-camera-placeholder" data-role="camera-placeholder">
                    {placeholder_message(camera, @choices, @watches, @webrtc?)}
                  </p>
                <% session -> %>
                  <video
                    id={video_id(camera.name, session)}
                    phx-hook="CameraPlayer"
                    phx-target={@myself}
                    phx-update="ignore"
                    class="bb-camera-video"
                    data-role="camera-preview"
                    data-camera={camera.name}
                    data-session={session}
                    data-ice-servers={Jason.encode!(@ice_servers)}
                    aria-label={"Live preview of #{Camera.label(camera)}"}
                    autoplay
                    muted
                    playsinline
                    disablepictureinpicture
                  >
                  </video>
              <% end %>
            </div>

            <div class="bb-camera-footer">
              <span class="bb-camera-stream">
                {stream_text(camera.stream)}
                <span
                  :if={watch_session(camera, @watches)}
                  id={"#{video_id(camera.name, watch_session(camera, @watches))}-playback"}
                  class="bb-camera-playback"
                  data-role="camera-playback"
                  phx-update="ignore"
                >
                </span>
              </span>
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
    </div>
    """
  end

  defp choice(camera, choices), do: Map.get(choices, Atom.to_string(camera.name))

  defp discover(socket, robot_module) do
    assign(socket,
      cameras: Camera.discover(robot_module),
      webrtc?: Camera.webrtc_available?()
    )
  end

  defp drop_watch(socket, name) do
    assign(socket, :watches, Map.delete(socket.assigns.watches, name))
  end

  defp empty_message do
    if Camera.available?() do
      "This robot declares no cameras"
    else
      "No camera package installed — add bb_camera and a driver to preview cameras here"
    end
  end

  # A message for a stream this component has already stopped or replaced
  # belongs to no watch, and is dropped.
  defp find_stream_event(socket, message) do
    Enum.find_value(socket.assigns.watches, fn
      {name, %{watch: watch} = entry} ->
        case Camera.stream_event(watch, message) do
          nil -> nil
          event -> {name, entry, event}
        end

      {_name, {:retrying, _session}} ->
        nil
    end)
  end

  defp handle_stream_event(socket, nil), do: socket

  defp handle_stream_event(socket, {name, entry, {:signal, message}}) do
    socket
    |> push_event("webrtc_signaling-#{video_id(name, entry.session)}", message)
    |> put_watch(name, %{entry | signalled?: true})
  end

  defp handle_stream_event(socket, {name, %{signalled?: true}, :ended}),
    do: socket |> drop_watch(name) |> settle()

  defp handle_stream_event(socket, {name, entry, :ended}),
    do: retry_later(socket, name, entry.session)

  defp put_watch(socket, name, watch) do
    assign(socket, :watches, Map.put(socket.assigns.watches, name, watch))
  end

  defp resolve(socket, name) do
    socket.assigns.cameras
    |> Enum.find(&(Atom.to_string(&1.name) == name))
    |> case do
      nil -> socket.assigns.selected
      camera -> Atom.to_string(camera.name)
    end
  end

  defp retry_later(socket, name, session) do
    send_update_after(socket.assigns.myself, [event: {:retry, name, session}], @retry_ms)
    put_watch(socket, name, {:retrying, session})
  end

  # Called after anything that can change which cameras are on screen. It
  # keeps a selection pointing at a camera that exists, forgets the intent to
  # watch anything that has just been taken off screen — silently watching it
  # again later would start a capture nobody asked for a second time; a pause
  # is a different thing and is kept — and then watches exactly what should
  # be playing.
  defp settle(socket) do
    socket = assign(socket, :selected, settled_selection(socket))
    showing = socket |> visible_cameras() |> MapSet.new(&Atom.to_string(&1.name))

    choices =
      Map.filter(socket.assigns.choices, fn {name, choice} ->
        choice == :off or MapSet.member?(showing, name)
      end)

    socket
    |> assign(:choices, choices)
    |> sync_watches()
  end

  defp settled_selection(%{assigns: %{cameras: []}}), do: nil

  defp settled_selection(%{assigns: %{cameras: cameras, selected: selected}}) do
    names = Enum.map(cameras, &Atom.to_string(&1.name))

    if selected in names, do: selected, else: List.first(names)
  end

  defp shown?(camera, selected), do: Atom.to_string(camera.name) == selected

  defp start_watch(socket, camera) do
    name = Atom.to_string(camera.name)
    session = Map.get(socket.assigns.sessions, name, 0) + 1
    socket = assign(socket, :sessions, Map.put(socket.assigns.sessions, name, session))

    case Camera.watch(socket.assigns.robot_module, camera.name,
           ice_servers: socket.assigns.ice_servers
         ) do
      {:ok, watch} ->
        put_watch(socket, name, %{watch: watch, session: session, signalled?: false})

      {:error, _reason} ->
        retry_later(socket, name, session)
    end
  end

  defp stop_watch(%{watch: watch}), do: Camera.unwatch(watch)
  defp stop_watch({:retrying, _session}), do: :ok

  defp stop_watches(socket) do
    socket.assigns.watches |> Map.values() |> Enum.each(&stop_watch/1)
    assign(socket, :watches, %{})
  end

  # Watches what should be playing, and stops what shouldn't. Nothing is
  # watched before the socket connects: the disconnected render has no
  # browser on the other end to play it.
  defp sync_watches(socket) do
    wanted =
      if connected?(socket) do
        socket
        |> visible_cameras()
        |> Enum.filter(&previewing?(&1, socket.assigns.choices))
      else
        []
      end

    wanted_names = MapSet.new(wanted, &Atom.to_string(&1.name))

    {keep, drop} =
      Map.split_with(socket.assigns.watches, fn {name, _watch} ->
        MapSet.member?(wanted_names, name)
      end)

    Enum.each(drop, fn {_name, watch} -> stop_watch(watch) end)

    wanted
    |> Enum.reject(&Map.has_key?(keep, Atom.to_string(&1.name)))
    |> Enum.reduce(assign(socket, :watches, keep), &start_watch(&2, &1))
  end

  defp video_id(name, session), do: "bb-camera-video-#{name}-#{session}"

  defp visible_cameras(%{assigns: assigns}), do: visible_cameras(assigns)

  defp visible_cameras(%{visible: false}), do: []
  defp visible_cameras(%{view: :grid, cameras: cameras}), do: cameras

  defp visible_cameras(%{cameras: cameras, selected: selected}) do
    Enum.filter(cameras, &shown?(&1, selected))
  end

  defp watch_session(camera, watches) do
    case Map.get(watches, Atom.to_string(camera.name)) do
      %{session: session} -> session
      _unwatched_or_retrying -> nil
    end
  end

  defp placeholder_message(%{status: :declared}, _choices, _watches, _webrtc?),
    do: "Offline — declared in the robot but not running"

  defp placeholder_message(_camera, _choices, _watches, false),
    do: "Previews need bb_camera_webrtc — add it to your application's dependencies"

  defp placeholder_message(%{previewable?: false, stream: nil}, _choices, _watches, _webrtc?),
    do: "Waiting for the driver to report a stream format"

  defp placeholder_message(%{previewable?: false, stream: stream}, _choices, _watches, _webrtc?),
    do: "#{inspect(stream.format)} can't be previewed; only raw :I420 streams can"

  defp placeholder_message(camera, choices, watches, _webrtc?) do
    cond do
      match?({:retrying, _session}, Map.get(watches, Atom.to_string(camera.name))) ->
        "The stream stopped — trying again shortly"

      previewing?(camera, choices) ->
        "Connecting…"

      choice(camera, choices) == :off ->
        "Paused"

      true ->
        "Idle — nothing is capturing. Start a preview to begin."
    end
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
