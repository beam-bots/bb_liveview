# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.DashboardLive do
  @moduledoc """
  Main LiveView for the BB Dashboard.

  Displays robot status and control widgets including:
  - Safety status and controls
  - Joint positions and sliders
  - Event stream monitor
  - Command execution
  - 3D visualisation
  - Parameter editor
  """

  use Phoenix.LiveView, layout: {BB.LiveView.Layouts, :app}

  import BB.LiveView.Components

  alias BB.LiveView.Camera
  alias BB.LiveView.Components.Cameras
  alias BB.LiveView.Components.Command
  alias BB.LiveView.Components.Drive
  alias BB.LiveView.Components.EventStream
  alias BB.LiveView.Components.JointControl
  alias BB.LiveView.Components.Parameters
  alias BB.LiveView.Components.Safety
  alias BB.LiveView.Components.Visualisation

  @joint_state_throttle_ms 33

  # The visual area holds one of these at a time. Both are expensive to run —
  # one drives a WebGL context, the other a video stream per camera — so only
  # the chosen one exists.
  #
  # Every tab stays in the tab order. The ARIA pattern asks for a roving
  # tabindex with arrow keys moving between tabs, but a roving tabindex
  # without those key handlers takes the inactive tabs out of the tab order
  # and leaves them reachable by nothing at all. Plain focusable buttons are
  # worse than the full pattern and much better than half of it.
  @tabs [visualisation: "3D view", cameras: "Cameras"]

  # Lifecycle events a camera publishes on the ordinary sensor topic. Frames
  # never appear here — only the fact that capture started or stopped — so
  # seeing one means the camera list is stale, not that there are pixels to
  # render.
  @camera_events [
    BB.Message.Camera.BeginCapture,
    BB.Message.Camera.EndCapture
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    robot_module = socket.assigns.robot_module

    socket =
      socket
      |> assign(:robot_name, get_robot_name(robot_module))
      |> assign(:connected, connected?(socket))
      |> assign(:loading, true)
      |> assign(:joint_positions, %{})
      |> assign(:tab, :visualisation)
      |> assign(:tabs, visualisation: "3D view")
      |> assign(:latest_joint_message, nil)
      |> assign(:joint_state_flush_scheduled, false)
      |> assign_new(:drive, fn -> nil end)
      |> assign_new(:ice_servers, fn -> [] end)

    if connected?(socket) do
      subscribe_to_robot(robot_module)
      send(self(), :load_robot_data)
    end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, resolve_tab(tab, socket.assigns.tabs))}
  end

  @impl Phoenix.LiveView
  def handle_info(:load_robot_data, socket) do
    tabs =
      if Camera.discover(socket.assigns.robot_module) == [],
        do: [visualisation: "3D view"],
        else: @tabs

    {:noreply, assign(socket, loading: false, tabs: tabs)}
  end

  def handle_info({:bb, [:state_machine], %BB.Message{payload: payload} = message}, socket) do
    new_state = payload.to
    in_error = new_state == :error
    armed = new_state in [:armed, :idle, :executing]

    send_update(Safety,
      id: "safety",
      event: {:state_changed, new_state, in_error}
    )

    send_update(JointControl,
      id: "joint_control",
      event: {:armed_changed, armed}
    )

    if socket.assigns.drive do
      send_update(Drive, id: "drive", event: {:armed_changed, armed})
    end

    send_update(Command,
      id: "command",
      event: {:state_changed, new_state}
    )

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, [:state_machine], message}
    )

    {:noreply, socket}
  end

  def handle_info(
        {:bb, [:sensor | _rest] = path, %BB.Message{payload: %module{}} = message},
        socket
      )
      when module in @camera_events do
    send_update(Cameras, id: "cameras", event: :cameras_changed)

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
  end

  def handle_info(
        {:bb, [:sensor | _rest] = path,
         %BB.Message{payload: %BB.Message.Sensor.JointState{} = js} = message},
        socket
      ) do
    # Each joint's estimator publishes its own single-joint JointState on its
    # own topic. Accumulate them into one running pose so a flush updates every
    # joint together — pushing only the latest single message per throttle
    # window makes the visualisation update one joint at a time and look jerky.
    positions = js.names |> Enum.zip(js.positions) |> Map.new()

    socket =
      socket
      |> assign(:joint_positions, Map.merge(socket.assigns.joint_positions, positions))
      |> assign(:latest_joint_message, {path, message})
      |> schedule_joint_state_flush()

    {:noreply, socket}
  end

  def handle_info(:flush_joint_state, %{assigns: %{latest_joint_message: nil}} = socket) do
    {:noreply, assign(socket, :joint_state_flush_scheduled, false)}
  end

  def handle_info(:flush_joint_state, socket) do
    {path, message} = socket.assigns.latest_joint_message
    positions = socket.assigns.joint_positions

    send_update(JointControl,
      id: "joint_control",
      event: {:positions_updated, positions}
    )

    update_visualisation(socket, positions)

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply,
     socket
     |> assign(:latest_joint_message, nil)
     |> assign(:joint_state_flush_scheduled, false)}
  end

  def handle_info(
        {:bb, [:param | path], %BB.Message{payload: %BB.Parameter.Changed{} = changed} = message},
        socket
      ) do
    send_update(Parameters,
      id: "parameters",
      event: {:parameter_changed, path, changed.new_value}
    )

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, [:param | path], message}
    )

    {:noreply, socket}
  end

  def handle_info({:bb, [:command | _] = path, %BB.Message{} = message}, socket) do
    send_update(Command,
      id: "command",
      event: :commands_changed
    )

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
  end

  def handle_info({:bb, path, %BB.Message{} = message}, socket) do
    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
  end

  # Direct notification from JointControl for immediate visualisation update
  def handle_info({:joint_position_changed, positions}, socket) do
    update_visualisation(socket, positions)

    {:noreply, socket}
  end

  # Command completion notification from Task
  def handle_info({:command_complete, component_id, {:ok, result}}, socket) do
    send_update(Command,
      id: component_id,
      event: {:command_result, result}
    )

    {:noreply, socket}
  end

  def handle_info({:command_complete, component_id, {:error, reason}}, socket) do
    send_update(Command,
      id: component_id,
      event: {:command_error, reason}
    )

    {:noreply, socket}
  end

  # The camera streams the Cameras component watches from this process send it
  # their signalling and their end. What those messages look like is the
  # camera implementation's business, so they are recognised by asking it.
  def handle_info(message, socket) do
    if Keyword.has_key?(socket.assigns.tabs, :cameras) and Camera.stream_message?(message) do
      send_update(Cameras, id: "cameras", event: {:stream_message, message})
    end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="bb-dashboard-container">
      <.header robot_name={@robot_name} connected={@connected} />

      <div class="bb-dashboard-content">
        <div :if={@loading} class="bb-dashboard-loading">
          <.spinner />
          <p>Loading robot data...</p>
        </div>

        <div :if={!@loading} class="bb-dashboard-grid">
          <div class="bb-dashboard-sidebar">
            <.widget title="Safety">
              <.live_component module={Safety} id="safety" robot_module={@robot_module} />
            </.widget>

            <.widget :if={@drive} title="Drive">
              <.live_component module={Drive} id="drive" robot_module={@robot_module} drive={@drive} />
            </.widget>

            <.widget title="Commands">
              <.live_component module={Command} id="command" robot_module={@robot_module} />
            </.widget>
          </div>

          <div class="bb-dashboard-main-area">
            <.widget title="View" class="bb-widget-visualisation">
              <div :if={length(@tabs) > 1} class="bb-view-tabs" role="tablist" aria-label="Visual area">
                <button
                  :for={{id, label} <- @tabs}
                  type="button"
                  role="tab"
                  id={"bb-view-tab-#{id}"}
                  class={["bb-view-tab", @tab == id && "active"]}
                  data-role="view-tab"
                  data-tab={id}
                  aria-selected={to_string(@tab == id)}
                  aria-controls={"bb-view-panel-#{id}"}
                  phx-click="select_tab"
                  phx-value-tab={id}
                >
                  {label}
                </button>
              </div>

              <div
                id="bb-view-panel-visualisation"
                role={if length(@tabs) > 1, do: "tabpanel"}
                aria-labelledby={if length(@tabs) > 1, do: "bb-view-tab-visualisation"}
                hidden={@tab != :visualisation}
              >
                <.live_component
                  :if={@tab == :visualisation}
                  module={Visualisation}
                  id="visualisation"
                  robot_module={@robot_module}
                />
              </div>

              <div
                :if={Keyword.has_key?(@tabs, :cameras)}
                id="bb-view-panel-cameras"
                role="tabpanel"
                aria-labelledby="bb-view-tab-cameras"
                hidden={@tab != :cameras}
              >
                <.live_component
                  module={Cameras}
                  id="cameras"
                  robot_module={@robot_module}
                  ice_servers={@ice_servers}
                  visible={@tab == :cameras}
                />
              </div>
            </.widget>

            <.widget title="Joint Control">
              <.live_component module={JointControl} id="joint_control" robot_module={@robot_module} />
            </.widget>
          </div>

          <div class="bb-dashboard-bottom">
            <.widget title="Event Stream">
              <.live_component module={EventStream} id="event_stream" robot_module={@robot_module} />
            </.widget>

            <.widget title="Parameters">
              <.live_component module={Parameters} id="parameters" robot_module={@robot_module} />
            </.widget>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp header(assigns) do
    ~H"""
    <header class="bb-dashboard-header">
      <h1 class="bb-dashboard-title">
        {@robot_name}
      </h1>
      <div class="bb-connection-status">
        <span class={"bb-status-indicator #{if @connected, do: "connected", else: "disconnected"}"}>
        </span>
        {if @connected, do: "Connected", else: "Connecting..."}
      </div>
    </header>
    """
  end

  # The 3D view only exists while its tab is chosen, and `send_update/3` to a
  # component that isn't rendered is an error rather than a no-op.
  defp update_visualisation(%{assigns: %{tab: :visualisation}}, positions) do
    send_update(Visualisation,
      id: "visualisation",
      event: {:positions_updated, positions}
    )
  end

  defp update_visualisation(_socket, _positions), do: :ok

  defp resolve_tab(tab, tabs) do
    Enum.find_value(tabs, :visualisation, fn {id, _label} ->
      if Atom.to_string(id) == tab, do: id
    end)
  end

  defp get_robot_name(robot_module) do
    robot_module
    |> Module.split()
    |> List.last()
  end

  defp schedule_joint_state_flush(%{assigns: %{joint_state_flush_scheduled: true}} = socket),
    do: socket

  defp schedule_joint_state_flush(socket) do
    Process.send_after(self(), :flush_joint_state, @joint_state_throttle_ms)
    assign(socket, :joint_state_flush_scheduled, true)
  end

  defp subscribe_to_robot(robot_module) do
    if valid_robot?(robot_module) do
      try do
        BB.subscribe(robot_module, [:state_machine])
        BB.subscribe(robot_module, [:sensor])
        BB.subscribe(robot_module, [:param])
        BB.subscribe(robot_module, [:command])
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
