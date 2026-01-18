<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to Customise Dashboard Layout

Create a custom LiveView that uses BB.LiveView components with your own layout.

## Prerequisites

- Completed [Your First Dashboard](../tutorials/01-your-first-dashboard.md)
- Understanding of Phoenix LiveView

## Step 1: Create a Custom LiveView

Instead of using the built-in dashboard, create your own LiveView that uses individual components:

```elixir
# lib/my_app_web/live/robot_live.ex
defmodule MyAppWeb.RobotLive do
  use MyAppWeb, :live_view

  alias BB.LiveView.Components.{Safety, JointControl, Visualisation, EventStream}

  @impl true
  def mount(_params, _session, socket) do
    robot_module = MyRobot
    robot = robot_module.robot()

    # Subscribe to robot events
    if connected?(socket) do
      BB.subscribe(robot_module, [:state_machine])
      BB.subscribe(robot_module, [:safety])
      BB.subscribe(robot_module, [:sensor])
    end

    {:ok, assign(socket,
      robot_module: robot_module,
      robot: robot,
      positions: initial_positions(robot)
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-4 p-4">
      <div class="col-span-1">
        <.live_component
          module={Safety}
          id="safety"
          robot_module={@robot_module}
          robot={@robot}
        />
      </div>

      <div class="col-span-2">
        <.live_component
          module={Visualisation}
          id="visualisation"
          robot_module={@robot_module}
          robot={@robot}
        />
      </div>

      <div class="col-span-3">
        <.live_component
          module={JointControl}
          id="joints"
          robot_module={@robot_module}
          robot={@robot}
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:bb, [:sensor | path], %{payload: joint_state}}, socket) do
    joint_name = List.last(path)
    positions = Map.put(socket.assigns.positions, joint_name, hd(joint_state.positions))

    send_update(Visualisation, id: "visualisation", event: {:positions_updated, positions})
    send_update(JointControl, id: "joints", event: {:positions_updated, positions})

    {:noreply, assign(socket, positions: positions)}
  end

  def handle_info({:bb, [:state_machine], %{payload: transition}}, socket) do
    send_update(Safety, id: "safety", event: {:state_changed, transition.to})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp initial_positions(robot) do
    robot.joints
    |> Map.keys()
    |> Map.new(fn name -> {name, 0.0} end)
  end
end
```

## Step 2: Route to Your LiveView

Add a route to your custom LiveView:

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser
  live "/robot", RobotLive
end

# Still need asset routes for JS/CSS
import BB.LiveView.Router
scope "/" do
  bb_dashboard "/__bb_dashboard__", MyRobot  # Hidden route just for assets
end
```

Alternatively, serve assets manually by adding the static plug:

```elixir
# lib/my_app_web/endpoint.ex
plug BB.LiveView.Plugs.Static
```

## Step 3: Handle Component Events

Components communicate through events. Handle them in your LiveView:

```elixir
@impl true
def handle_info({:joint_position_changed, positions}, socket) do
  # Slider was moved - update visualisation immediately
  send_update(Visualisation, id: "visualisation", event: {:positions_updated, positions})
  {:noreply, socket}
end

def handle_info({:command_result, result}, socket) do
  # Command completed - show notification
  {:noreply, put_flash(socket, :info, "Command result: #{inspect(result)}")}
end
```

## Step 4: Select Components

Use only the components you need:

```elixir
# Minimal control interface
def render(assigns) do
  ~H"""
  <div class="flex gap-4">
    <.live_component module={Safety} id="safety" robot_module={@robot_module} robot={@robot} />
    <.live_component module={JointControl} id="joints" robot_module={@robot_module} robot={@robot} />
  </div>
  """
end

# Monitoring only (no control)
def render(assigns) do
  ~H"""
  <div class="grid grid-cols-2 gap-4">
    <.live_component module={Visualisation} id="vis" robot_module={@robot_module} robot={@robot} />
    <.live_component module={EventStream} id="events" robot_module={@robot_module} />
  </div>
  """
end
```

## Available Components

| Component | Module | Purpose |
|-----------|--------|---------|
| Safety | `BB.LiveView.Components.Safety` | Arm/disarm controls |
| JointControl | `BB.LiveView.Components.JointControl` | Position sliders |
| Visualisation | `BB.LiveView.Components.Visualisation` | 3D view |
| EventStream | `BB.LiveView.Components.EventStream` | Message monitor |
| Command | `BB.LiveView.Components.Command` | Command forms |
| Parameters | `BB.LiveView.Components.Parameters` | Parameter editor |

## Component Props

All components require:
- `id` - Unique identifier for LiveComponent
- `robot_module` - Your robot module (e.g., `MyRobot`)
- `robot` - The compiled robot struct from `robot_module.robot()`

## Styling

Components use Tailwind CSS classes. Override styles by:

1. Adding custom CSS after the BB assets
2. Using CSS specificity to override defaults
3. Wrapping components in custom containers

```heex
<div class="my-custom-wrapper">
  <.live_component module={Safety} id="safety" ... />
</div>
```

## Common Patterns

### Responsive Layout

```heex
<div class="flex flex-col lg:flex-row gap-4">
  <div class="lg:w-1/3">
    <.live_component module={Safety} ... />
    <.live_component module={JointControl} ... />
  </div>
  <div class="lg:w-2/3">
    <.live_component module={Visualisation} ... />
  </div>
</div>
```

### Tabbed Interface

```heex
<div>
  <div class="tabs">
    <button phx-click="tab" phx-value-tab="control">Control</button>
    <button phx-click="tab" phx-value-tab="monitor">Monitor</button>
  </div>

  <%= case @tab do %>
    <% "control" -> %>
      <.live_component module={JointControl} ... />
    <% "monitor" -> %>
      <.live_component module={EventStream} ... />
  <% end %>
</div>
```

## Troubleshooting

### Components not updating

Ensure you're:
1. Subscribed to the correct PubSub channels
2. Forwarding events with `send_update/3`
3. Using unique component IDs

### 3D visualisation not rendering

Check that:
1. The Three.js assets are being served
2. The component has a container with height
3. WebGL is available in the browser
