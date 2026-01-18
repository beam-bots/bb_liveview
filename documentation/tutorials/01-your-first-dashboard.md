<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Your First Dashboard

In this tutorial, you'll add a real-time control dashboard to a Phoenix application with a Beam Bots robot.

## What We're Building

A browser-based dashboard that provides:
- Safety controls (arm/disarm)
- Joint position sliders
- 3D robot visualisation
- Real-time event stream
- Command execution forms
- Parameter editor

## Prerequisites

- A Phoenix application
- A BB robot module (see [First Robot](https://hexdocs.pm/bb/01-first-robot.html))
- Basic familiarity with Phoenix routing

## Step 1: Add the Dependency

Add `bb_liveview` to your `mix.exs`:

```elixir
defp deps do
  [
    {:bb, "~> 0.12"},
    {:bb_liveview, "~> 0.1"},
    # ... other deps
  ]
end
```

Run `mix deps.get`.

## Step 2: Configure the Router

Import the router helpers and mount the dashboard at a path:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import BB.LiveView.Router

  # ... existing pipelines ...

  scope "/" do
    pipe_through :browser
    bb_dashboard "/robot", MyRobot
  end
end
```

The `bb_dashboard/2` macro generates:
- Asset routes at `/__bb_assets__/*`
- LiveView route at your specified path

## Step 3: Start the Robot

Ensure your robot starts with your application. In your application supervisor:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start robot in simulation mode (or without :simulation for real hardware)
      {BB.Supervisor, {MyRobot, simulation: :kinematic}},
      MyAppWeb.Endpoint,
      # ... other children
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Step 4: View the Dashboard

Start your Phoenix server:

```bash
mix phx.server
```

Navigate to `http://localhost:4000/robot` in your browser.

You'll see the dashboard with all components:

- **Safety panel** (top left) - Shows current state, arm/disarm buttons
- **Joint control** (left) - Sliders for each joint
- **3D visualisation** (centre) - Interactive robot view
- **Event stream** (right) - Real-time PubSub messages
- **Commands** (bottom) - Forms for executing commands
- **Parameters** (bottom right) - Runtime parameter editor

## Step 5: Interact with the Robot

### Arm the Robot

Click the **Arm** button in the safety panel. The status changes from "Disarmed" to "Idle".

### Move Joints

With the robot armed, drag the joint sliders. The 3D visualisation updates in real-time, and you'll see `JointState` messages in the event stream.

### Execute Commands

If your robot defines commands (like `move_to`), fill in the form fields and click execute. Results appear below the form.

### Monitor Events

The event stream shows all PubSub messages. Use the filter input to narrow by path (e.g., `sensor.shoulder`).

### Disarm

Click **Disarm** to safely stop the robot. Joint sliders become disabled.

## Understanding the Components

### Safety Component

Subscribes to `[:state_machine]` and `[:safety]` channels. Displays:
- Current operational state
- Arm/disarm buttons (enabled based on state)
- Error messages if disarm fails

### Joint Control Component

Reads joint definitions from the robot struct. For each joint:
- Shows current position (degrees for revolute, mm for prismatic)
- Provides a slider respecting joint limits
- Sends position commands via `BB.Actuator.set_position/4`

### 3D Visualisation Component

Uses Three.js to render the robot:
- Builds model from robot topology (links, joints, visuals)
- Updates joint positions in real-time via WebSocket
- Supports orbit controls (rotate, pan, zoom)

### Event Stream Component

Subscribes to all robot PubSub channels. Features:
- Path-based filtering
- Pause/resume
- Expandable message details
- Auto-scroll

### Command Component

Generates forms from command definitions:
- Reads arguments from DSL
- Validates input types
- Shows execution results

### Parameters Component

Displays runtime parameters from `BB.Parameter`:
- Grouped by category
- Editable values
- Real-time updates

## Simulation vs Real Hardware

In simulation mode (`simulation: :kinematic`):
- No hardware drivers are started
- Actuators use `BB.Sim.Actuator` with timing based on velocity limits
- Position feedback comes from `OpenLoopPositionEstimator`
- Safety system still requires arming

For real hardware:
- Remove the `:simulation` option
- Ensure hardware drivers (controllers, actuators) are properly configured
- The dashboard works identically

## Next Steps

- [Customise Dashboard Layout](../how-to/customise-dashboard-layout.md) - Create a custom layout
- Add authentication to protect the dashboard
- Deploy to production with proper asset compilation
