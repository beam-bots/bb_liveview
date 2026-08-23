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

  alias BB.Math.Quaternion
  alias BB.Math.Transform
  alias BB.Math.Transform2D
  alias BB.Math.Vec3
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
    serialized = serialize_positions(positions, socket.assigns.topology)
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
        topology = serialize_topology(robot_struct)

        socket
        |> assign(:robot_module, robot_module)
        |> assign(:topology, topology)
        |> assign(:positions, serialize_positions(positions, topology))
        |> assign(:robot_name, robot_name)

      :error ->
        assign(socket, :robot_module, robot_module)
    end
  end

  defp load_robot_data(robot_module) do
    if valid_robot?(robot_module) do
      try do
        robot_struct = RobotRuntime.get_robot(robot_module)
        positions = RobotRuntime.configurations(robot_module)
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

  defp serialize_positions(positions, topology) do
    joints = topology_joints(topology)

    Map.new(positions, fn {joint_name, configuration} ->
      name = Atom.to_string(joint_name)
      {name, serialize_configuration(configuration, Map.get(joints, name))}
    end)
  end

  defp topology_joints(%{joints: joints}), do: joints
  defp topology_joints(_topology), do: %{}

  defp serialize_configuration(configuration, _joint) when is_number(configuration),
    do: configuration

  # A planar configuration only means anything alongside the plane normal it was
  # measured against, and a floating one is already a full pose. Lifting the
  # planar case here — through the same `Transform2D.to_transform/2` forward
  # kinematics uses — keeps the plane basis convention in `bb`, and leaves the
  # browser a pose it can apply without knowing about either.
  defp serialize_configuration(%Transform2D{} = configuration, joint) do
    configuration
    |> Transform2D.to_transform(plane_normal(joint))
    |> serialize_pose()
  end

  defp serialize_configuration(%Transform{} = configuration, _joint),
    do: serialize_pose(configuration)

  defp plane_normal(%{axis: %{x: x, y: y, z: z}}), do: Vec3.new(x, y, z)
  defp plane_normal(_joint), do: Vec3.unit_z()

  defp serialize_pose(transform) do
    [x, y, z] = transform |> Transform.get_translation() |> Vec3.to_list()
    [qx, qy, qz, qw] = transform |> Transform.get_quaternion() |> Quaternion.to_xyzw_list()

    %{
      xyz: %{x: x, y: y, z: z},
      quat: %{x: qx, y: qy, z: qz, w: qw}
    }
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
