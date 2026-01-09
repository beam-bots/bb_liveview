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

  alias BB.LiveView.Components.Command
  alias BB.LiveView.Components.EventStream
  alias BB.LiveView.Components.JointControl
  alias BB.LiveView.Components.Parameters
  alias BB.LiveView.Components.Safety
  alias BB.LiveView.Components.Visualisation

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    robot_module = socket.assigns.robot_module

    socket =
      socket
      |> assign(:robot_name, get_robot_name(robot_module))
      |> assign(:connected, connected?(socket))
      |> assign(:loading, true)

    if connected?(socket) do
      subscribe_to_robot(robot_module)
      send(self(), :load_robot_data)
    end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:load_robot_data, socket) do
    {:noreply, assign(socket, :loading, false)}
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
        {:bb, [:sensor | _rest] = path,
         %BB.Message{payload: %BB.Message.Sensor.JointState{} = js} = message},
        socket
      ) do
    positions =
      Enum.zip(js.names, js.positions)
      |> Map.new()

    send_update(JointControl,
      id: "joint_control",
      event: {:positions_updated, positions}
    )

    send_update(Visualisation,
      id: "visualisation",
      event: {:positions_updated, positions}
    )

    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
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

  def handle_info({:bb, path, %BB.Message{} = message}, socket) do
    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
  end

  # Direct notification from JointControl for immediate visualisation update
  def handle_info({:joint_position_changed, positions}, socket) do
    send_update(Visualisation,
      id: "visualisation",
      event: {:positions_updated, positions}
    )

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

  def handle_info(_msg, socket) do
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

            <.widget title="Commands">
              <.live_component module={Command} id="command" robot_module={@robot_module} />
            </.widget>
          </div>

          <div class="bb-dashboard-main-area">
            <.widget title="3D Visualisation" class="bb-widget-visualisation">
              <.live_component module={Visualisation} id="visualisation" robot_module={@robot_module} />
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

  defp get_robot_name(robot_module) do
    robot_module
    |> Module.split()
    |> List.last()
  end

  defp subscribe_to_robot(robot_module) do
    if valid_robot?(robot_module) do
      try do
        BB.subscribe(robot_module, [:state_machine])
        BB.subscribe(robot_module, [:sensor])
        BB.subscribe(robot_module, [:param])
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
