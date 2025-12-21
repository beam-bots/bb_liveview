# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.JointControl do
  @moduledoc """
  LiveComponent for controlling robot joint positions.

  Displays a table of all movable joints with:
  - Joint name and type
  - Current position (updated in real-time)
  - Position limits (min/max)
  - Slider for setting target position

  Controls are only enabled when the robot is armed.
  """
  use Phoenix.LiveComponent

  alias BB.Message
  alias BB.Message.Actuator.Command
  alias BB.Robot.Runtime, as: RobotRuntime

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       joints: [],
       armed: false,
       error_message: nil
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:positions_updated, positions}}, socket) do
    updated_joints =
      Enum.map(socket.assigns.joints, fn joint ->
        case Map.get(positions, joint.name) do
          nil -> joint
          pos -> %{joint | position: pos}
        end
      end)

    {:ok, assign(socket, :joints, updated_joints)}
  end

  def update(%{event: {:armed_changed, armed}}, socket) do
    {:ok, assign(socket, :armed, armed)}
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] != robot_module do
        case load_robot_data(robot_module) do
          {:ok, robot_struct, positions, armed} ->
            joints = build_joint_data(robot_struct, positions)

            socket
            |> assign(:robot_module, robot_module)
            |> assign(:robot_struct, robot_struct)
            |> assign(:joints, joints)
            |> assign(:armed, armed)

          :error ->
            assign(socket, :robot_module, robot_module)
        end
      else
        socket
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-joint-control">
      <div class="bb-joint-header">
        <span class={"bb-armed-badge #{if @armed, do: "armed", else: "disarmed"}"}>
          {if @armed, do: "Armed", else: "Disarmed"}
        </span>
      </div>

      <div :if={@error_message} class="bb-error-message" role="alert">
        <span class="bb-error-icon">!</span>
        <span>{@error_message}</span>
      </div>

      <div :if={@joints == []} class="bb-empty-state">
        <p class="bb-empty-state-message">No movable joints found</p>
      </div>

      <div :if={@joints != []} class="bb-joint-table">
        <div class="bb-joint-table-header">
          <span class="bb-joint-col-name">Joint</span>
          <span class="bb-joint-col-type">Type</span>
          <span class="bb-joint-col-position">Position</span>
          <span class="bb-joint-col-slider">Target</span>
        </div>

        <div class="bb-joint-table-body">
          <div
            :for={joint <- @joints}
            class={"bb-joint-row #{if joint.actuator == nil, do: "simulated", else: ""}"}
          >
            <span class="bb-joint-col-name">
              {joint.name}
              <span :if={joint.actuator == nil} class="bb-sim-badge">sim</span>
            </span>
            <span class="bb-joint-col-type">{joint.type}</span>
            <span class="bb-joint-col-position">{format_position(joint.position, joint.type)}</span>
            <span class="bb-joint-col-slider">
              <form phx-change="set_position" phx-target={@myself}>
                <span class="bb-limit-label">{format_limit(joint.lower_limit, joint.type)}</span>
                <input type="hidden" name="joint" value={joint.name} />
                <input
                  type="range"
                  name="value"
                  class="bb-slider"
                  min={slider_min(joint)}
                  max={slider_max(joint)}
                  step={slider_step(joint)}
                  value={joint.position}
                  disabled={not @armed}
                  phx-debounce="16"
                />
                <span class="bb-limit-label">{format_limit(joint.upper_limit, joint.type)}</span>
              </form>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_position", %{"joint" => joint_name, "value" => value}, socket) do
    {position, ""} = Float.parse(value)
    joint_atom = String.to_existing_atom(joint_name)

    socket =
      if socket.assigns.armed and valid_robot?(socket.assigns.robot_module) do
        case find_joint(socket.assigns.joints, joint_atom) do
          nil ->
            socket

          %{actuator: nil} = _joint ->
            send_simulated_position(socket, joint_atom, position)

          joint ->
            send_position_command(
              socket.assigns.robot_module,
              joint_atom,
              joint.actuator,
              position
            )

            socket
        end
      else
        if valid_robot?(socket.assigns.robot_module) do
          assign(socket, :error_message, "Robot must be armed to control joints")
        else
          assign(socket, :error_message, "No valid robot connected")
        end
      end

    {:noreply, socket}
  end

  defp build_joint_data(robot_struct, positions) do
    robot_struct.joints
    |> Enum.filter(fn {_name, joint} -> movable_joint?(joint) end)
    |> Enum.map(fn {name, joint} ->
      actuator = find_actuator_for_joint(robot_struct, name)
      position = Map.get(positions, name, 0.0)

      %{
        name: name,
        type: joint.type,
        position: position,
        lower_limit: get_limit(joint, :lower),
        upper_limit: get_limit(joint, :upper),
        actuator: actuator
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp movable_joint?(joint) do
    joint.type in [:revolute, :continuous, :prismatic]
  end

  defp get_limit(joint, which) do
    case joint.limits do
      nil -> nil
      limits -> Map.get(limits, which)
    end
  end

  defp find_actuator_for_joint(robot_struct, joint_name) do
    robot_struct.actuators
    |> Enum.find(fn {_name, info} -> info.joint == joint_name end)
    |> case do
      {actuator_name, _info} -> actuator_name
      nil -> nil
    end
  end

  defp find_joint(joints, name), do: Enum.find(joints, fn j -> j.name == name end)

  defp send_position_command(robot, joint_name, actuator_name, position) do
    {:ok, msg} = Message.new(Command.Position, joint_name, position: position * 1.0)
    BB.publish(robot, [:actuator, joint_name, actuator_name], msg)
  end

  defp send_simulated_position(socket, joint_name, position) do
    updated_joints =
      Enum.map(socket.assigns.joints, fn joint ->
        if joint.name == joint_name do
          %{joint | position: position}
        else
          joint
        end
      end)

    # Notify parent directly for immediate visualisation update
    send(self(), {:joint_position_changed, %{joint_name => position}})

    # Also publish to PubSub for other subscribers
    {:ok, msg} =
      Message.new(BB.Message.Sensor.JointState, :simulated,
        names: [joint_name],
        positions: [position * 1.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    BB.publish(socket.assigns.robot_module, [:sensor, :simulated], msg)

    assign(socket, :joints, updated_joints)
  end

  defp format_position(pos, _type) when is_nil(pos), do: "N/A"

  defp format_position(pos, :prismatic) do
    "#{Float.round(pos * 1000, 1)} mm"
  end

  defp format_position(pos, _type) do
    degrees = pos * 180 / :math.pi()
    "#{Float.round(degrees, 1)}°"
  end

  defp format_limit(nil, _type), do: "∞"

  defp format_limit(limit, :prismatic) do
    "#{round(limit * 1000)}"
  end

  defp format_limit(limit, _type) do
    "#{round(limit * 180 / :math.pi())}"
  end

  defp slider_min(%{lower_limit: nil}), do: -:math.pi()
  defp slider_min(%{lower_limit: limit}), do: limit

  defp slider_max(%{upper_limit: nil}), do: :math.pi()
  defp slider_max(%{upper_limit: limit}), do: limit

  defp slider_step(joint) do
    min = slider_min(joint)
    max = slider_max(joint)
    (max - min) / 100
  end

  defp load_robot_data(robot_module) do
    if valid_robot?(robot_module) do
      try do
        robot_struct = RobotRuntime.get_robot(robot_module)
        positions = RobotRuntime.positions(robot_module)
        armed = BB.Safety.armed?(robot_module)
        {:ok, robot_struct, positions, armed}
      rescue
        ArgumentError -> :error
      end
    else
      :error
    end
  end

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
