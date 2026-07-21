<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# BB.LiveView Usage Rules

`bb_liveview` provides `BB.LiveView.Router.bb_dashboard/2`, a Phoenix LiveView
dashboard for a running [Beam Bots](https://hexdocs.pm/bb) robot — live joint
state, a 3D model, command forms, a PubSub event stream, and arm/disarm safety
controls. For BB framework basics, see `bb`'s rules
(`mix usage_rules.sync <file> bb:all`); this file covers only how to mount and
use the dashboard.

## Core principles

1. **The dashboard is a router mount, not a DSL component.** It is *not* a
   `BB.Sensor`/`BB.Actuator`/`BB.Controller` and it does *not* go in the robot's
   `topology`. You mount it into your host Phoenix app's router with
   `bb_dashboard/2`.
2. **It observes a robot that is already running.** On mount it subscribes to
   the robot's PubSub (`:state_machine`, `:sensor`, `:param`) and reads live
   state. The robot's supervision tree must be started separately — the
   dashboard neither starts nor supervises the robot.
3. **Serve the bundled assets at the endpoint, not through the router.** The
   Three.js/CSS bundle must be served by a `Plug.Static` in your endpoint,
   *before* `Plug.Session`. Serving it through the `:browser` pipeline trips
   Phoenix's CSRF cross-origin protection and 403s the `dashboard.js` load.

## Mounting it

Import the macro and mount it inside a `:browser`-piped scope:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import BB.LiveView.Router

  scope "/" do
    pipe_through :browser
    bb_dashboard "/robot", robot: MyApp.Robot
  end
end
```

Then add the asset plug to your endpoint, **before** `Plug.Session`:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  plug Plug.Static,
    at: "/__bb_assets__",
    from: {:bb_liveview, "priv/static"},
    gzip: false

  # ... plug Plug.Session, ... plug MyAppWeb.Router
end
```

And make sure the robot is supervised in your application:

```elixir
children = [
  {Phoenix.PubSub, name: MyApp.PubSub},
  {MyApp.Robot, []},
  MyAppWeb.Endpoint
]
```

The igniter installer wires all three up for you (and bootstraps a minimal
Phoenix app if the project has none):

```bash
mix igniter.install bb_liveview --path /robot --robot MyApp.Robot
```

## Options

`bb_dashboard/2` takes a path and a keyword list.

| Option | Required | Meaning |
|---|---|---|
| `:robot` | yes | The robot module. Must `use BB` (i.e. export `robot/0`) |

Mount it more than once for multiple robots — each call gets its own
`live_session`:

```elixir
scope "/" do
  pipe_through :browser
  bb_dashboard "/arm", robot: MyApp.ArmRobot
  bb_dashboard "/base", robot: MyApp.MobileBase
end
```

Motion controls stay disabled until you arm the robot from the safety widget;
this is the running robot's safety state, not a dashboard setting.

## Anti-patterns

- **Don't declare the dashboard in `topology`.** There is no component to
  supervise — it is a `bb_dashboard/2` router mount in the host app, driven
  purely by the robot's PubSub.
- **Don't serve the assets through the router/`:browser` pipeline.** The
  `Plug.Static` for `/__bb_assets__` belongs in the endpoint ahead of
  `Plug.Session`, or the CSRF check 403s the script.
- **Don't mount against a robot that isn't started.** The module must export
  `robot/0` *and* have its supervision tree running; otherwise the page renders
  but shows no live state and controls do nothing.

## Further reading

- [bb_liveview docs](https://hexdocs.pm/bb_liveview) — including
  [Your First Dashboard](https://hexdocs.pm/bb_liveview/01-your-first-dashboard.html)
- `bb`'s rules (`mix usage_rules.sync <file> bb:all`) and the
  [bb docs](https://hexdocs.pm/bb)
