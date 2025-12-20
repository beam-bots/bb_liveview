# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Visualisation do
  @moduledoc """
  LiveComponent for 3D robot visualisation using Three.js.

  Displays an interactive 3D view of the robot with:
  - Real-time joint position updates
  - Orbit camera controls (pan, zoom, rotate)
  - Visual geometry rendering (boxes, cylinders, spheres)
  """
  use Phoenix.LiveComponent

  alias BB.Robot.Runtime, as: RobotRuntime

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       topology: nil,
       positions: %{},
       robot_name: "Robot"
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:positions_updated, positions}}, socket) do
    serialized = serialize_positions(positions)
    {:ok, push_event(socket, "positions_updated", %{positions: serialized})}
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] != robot_module do
        initialize_for_robot(socket, robot_module)
      else
        socket
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp initialize_for_robot(socket, robot_module) do
    case load_robot_data(robot_module) do
      {:ok, robot_struct, positions} ->
        robot_name = get_robot_name(robot_module)

        socket
        |> assign(:robot_module, robot_module)
        |> assign(:topology, serialize_topology(robot_struct))
        |> assign(:positions, serialize_positions(positions))
        |> assign(:robot_name, robot_name)

      :error ->
        assign(socket, :robot_module, robot_module)
    end
  end

  defp load_robot_data(robot_module) do
    if valid_robot?(robot_module) do
      try do
        robot_struct = RobotRuntime.get_robot(robot_module)
        positions = RobotRuntime.positions(robot_module)
        {:ok, robot_struct, positions}
      rescue
        ArgumentError -> :error
      end
    else
      :error
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="bb-visualisation"
      phx-hook="Visualisation"
      data-topology={Jason.encode!(@topology || %{})}
      data-positions={Jason.encode!(@positions || %{})}
      data-robot-name={@robot_name}
    >
      <div :if={@topology == nil} class="bb-empty-state">
        <p class="bb-empty-state-message">Loading visualisation...</p>
      </div>
    </div>
    """
  end

  # Serialization helpers - convert Elixir structs to JSON-compatible maps

  defp serialize_topology(robot_struct) do
    %{
      name: Atom.to_string(robot_struct.name),
      links: serialize_links(robot_struct.links),
      joints: serialize_joints(robot_struct.joints)
    }
  end

  defp serialize_links(links) do
    links
    |> Enum.map(fn {name, link} ->
      {Atom.to_string(name), serialize_link(link)}
    end)
    |> Map.new()
  end

  defp serialize_link(link) do
    %{
      name: Atom.to_string(link.name),
      visual: serialize_visual(link.visual)
    }
  end

  defp serialize_visual(nil), do: nil

  defp serialize_visual(visual) do
    %{
      origin: serialize_origin(visual.origin),
      geometry: serialize_geometry(visual.geometry),
      material: serialize_material(visual.material)
    }
  end

  defp serialize_origin(nil), do: nil

  defp serialize_origin({position, orientation}) do
    {px, py, pz} = position
    {r, p, y} = orientation

    %{
      xyz: %{x: px, y: py, z: pz},
      rpy: %{r: r, p: p, y: y}
    }
  end

  defp serialize_geometry(nil), do: nil

  defp serialize_geometry({:box, dims}) do
    %{type: "box", x: dims.x, y: dims.y, z: dims.z}
  end

  defp serialize_geometry({:cylinder, dims}) do
    %{type: "cylinder", radius: dims.radius, length: dims[:height] || dims[:length]}
  end

  defp serialize_geometry({:sphere, dims}) do
    %{type: "sphere", radius: dims.radius}
  end

  defp serialize_geometry({:mesh, info}) do
    %{
      type: "mesh",
      filename: info.filename,
      scale: serialize_scale(info[:scale])
    }
  end

  defp serialize_scale(nil), do: %{x: 1, y: 1, z: 1}
  defp serialize_scale(scale) when is_number(scale), do: %{x: scale, y: scale, z: scale}
  defp serialize_scale({x, y, z}), do: %{x: x, y: y, z: z}
  defp serialize_scale(%{x: x, y: y, z: z}), do: %{x: x, y: y, z: z}

  defp serialize_material(nil), do: nil

  defp serialize_material(material) do
    %{
      name: material[:name] && Atom.to_string(material.name),
      colour: serialize_colour(material[:color])
    }
  end

  defp serialize_colour(nil), do: nil

  defp serialize_colour(%{red: r, green: g, blue: b, alpha: a}),
    do: %{rgba: %{r: r, g: g, b: b, a: a}}

  defp serialize_colour({r, g, b, a}), do: %{rgba: %{r: r, g: g, b: b, a: a}}
  defp serialize_colour({r, g, b}), do: %{r: r, g: g, b: b}

  defp serialize_joints(joints) do
    joints
    |> Enum.map(fn {name, joint} ->
      {Atom.to_string(name), serialize_joint(joint)}
    end)
    |> Map.new()
  end

  defp serialize_joint(joint) do
    %{
      name: Atom.to_string(joint.name),
      type: Atom.to_string(joint.type),
      parent: Atom.to_string(joint.parent_link),
      child: Atom.to_string(joint.child_link),
      origin: serialize_joint_origin(joint.origin),
      axis: serialize_axis(joint.axis),
      limits: serialize_limits(joint.limits)
    }
  end

  defp serialize_joint_origin(nil), do: nil

  defp serialize_joint_origin(origin) do
    {px, py, pz} = origin.position
    {r, p, y} = origin.orientation

    %{
      xyz: %{x: px, y: py, z: pz},
      rpy: %{r: r, p: p, y: y}
    }
  end

  defp serialize_axis(nil), do: %{x: 0, y: 0, z: 1}
  defp serialize_axis({x, y, z}), do: %{x: x, y: y, z: z}

  defp serialize_limits(nil), do: nil

  defp serialize_limits(limits) do
    %{
      lower: limits[:lower],
      upper: limits[:upper]
    }
  end

  defp serialize_positions(positions) do
    positions
    |> Enum.map(fn {name, value} ->
      {Atom.to_string(name), value}
    end)
    |> Map.new()
  end

  defp get_robot_name(robot_module) do
    robot_module
    |> Module.split()
    |> List.last()
  end

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
