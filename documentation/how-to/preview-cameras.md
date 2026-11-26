<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Preview cameras on the dashboard

The dashboard finds a robot's cameras by itself and previews them over
WebRTC. Mount `bb_dashboard` as usual, install two packages, and any camera
the robot declares appears in the Cameras tab.

## Requirements

- **`bb_camera`**, and a camera driver delivering raw `:I420` frames — which is
  what every `bb_camera` driver produces.
- **`bb_camera_webrtc`**, which encodes each camera once (H.264, tuned for
  latency) and streams it to every browser watching.
- **An override for `decimal`.** Membrane's `ratio` still declares
  `decimal ~> 1.6 or ~> 2.0`, below what `bb` wants and below the releases that
  fix `decimal`'s DoS advisories. `ratio` treats `decimal` as optional, so the
  override is safe, and Mix only honours it from your own `mix.exs`.

```elixir
def deps do
  [
    {:bb_liveview, "~> 0.4"},
    {:bb_camera, "~> 0.2"},
    {:bb_camera_webrtc, "~> 0.1"},
    {:decimal, "~> 3.0", override: true}
  ]
end
```

Both camera packages are optional dependencies of `bb_liveview`. Without
`bb_camera` there are no cameras to find, and the dashboard is exactly as it
was. With `bb_camera` but not `bb_camera_webrtc`, cameras are listed and each
tile says what to add to preview it.

The encoder runs on the CPU. At 640×480 and 30 fps libx264 takes about a fifth
of a laptop core; on a Raspberry Pi 4 or 5 expect most of one. It runs once per
camera, however many browsers are watching.

## What a camera is

A camera is an ordinary `BB.Sensor` that also implements `BB.Camera`, declared
like any other sensor:

```elixir
topology do
  link :base_link do
    sensor :head_camera, {BB.Camera.V4L, device: "/dev/video0"}
  end
end
```

## How video reaches the browser

**Not over the LiveView socket.** Video travels from the robot to the browser
over WebRTC. The socket carries only the signalling that sets each connection
up — an SDP offer and answer, and ICE candidates — and PubSub carries only
lifecycle events (capture started, capture ended), which the dashboard uses to
keep the camera list honest.

The dashboard's LiveView process watches each camera on screen with
`BB.LiveView.Camera.watch/3`, which calls `BB.Camera.WebRTC.watch/4`, and
stops watching one that goes off screen with `BB.Camera.WebRTC.unwatch/3`,
leaving the others playing. The first viewer of a camera starts its pipeline and the last to leave stops it,
which releases the camera; everyone in between shares one encoder. In the
browser, the `CameraPlayer` hook — `bb_camera_webrtc`'s player, bundled into
the dashboard's JavaScript — answers the offer and plays the stream in a
`<video>`, asking the browser for its smallest jitter buffer and showing the
connection state and the frame rate it is actually playing.

When a stream ends — the camera stopped or restarted, the browser's connection
failed — a camera still on screen is watched again straight away, in a new
session with a new `<video>` element. A camera that can't be streamed at all
right now is tried again every couple of seconds rather than in a tight loop.

## Networks

**No STUN or TURN servers are used by default.** The browser has to be able to
reach the robot directly: the same network, or a VPN such as Tailscale. That
is the common case for a robot, and it means nothing leaves your network.

A browser behind NAT — a phone on mobile data, say — can't reach the robot
that way, and needs a TURN server to relay through. Give the dashboard its ICE
servers with `:ice_servers`; they are used by both ends of every connection:

```elixir
bb_dashboard "/robot",
  robot: MyRobot,
  ice_servers: [
    %{urls: "stun:stun.example.com:3478"},
    %{urls: "turn:turn.example.com:3478", username: "robot", credential: "secret"}
  ]
```

TURN credentials are usually read at runtime, and often expire. A list written
into the router is compiled into your application, so pass a
`{module, function, args}` instead — it is called every time the dashboard
mounts:

```elixir
bb_dashboard "/robot", robot: MyRobot, ice_servers: {MyApp.Turn, :ice_servers, []}
```

The servers are handed to the browser, which needs them too, so anyone who can
open the dashboard can read them. Prefer short-lived TURN credentials.

## Authentication

Signalling travels over the dashboard's own LiveView socket, so whatever
pipeline guards the dashboard guards the previews. There is no extra route to
protect:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_admin]
  bb_dashboard "/robot", robot: MyRobot
end
```

## Where the previews live

The dashboard's visual area is one panel with two tabs — **3D view** and
**Cameras** — and opens on the 3D view. Safety, commands, joint control, the
event stream and parameters are always on screen; only the expensive half is
exclusive, because a WebGL context and a set of live video streams are not
things to run side by side for no reason.

The Cameras tab shows **one camera at a time**, picked from a selector, with a
**Compare all** button for a grid when you want to see them together. Anything
taken off screen — by switching tab, by choosing another camera, by leaving
the grid — stops being watched. That doesn't necessarily stop the camera:
another browser may be watching it.

A preview you started and then navigated away from does not resume by itself
when you come back; that would restart a capture you only asked for once.
Pressing Start again is one click. A camera that is still *capturing* when you
return shows straight away, as it always does.

## Opening the dashboard doesn't start anything

Watching a camera is what starts its capture, so a camera that is running but
not capturing shows a **Start capturing** button and no picture. Nothing is
watched until you press it. A dashboard with four cameras on it costs nothing
to open.

A camera that is *already* capturing previews immediately — watching it costs
the bandwidth, but it doesn't start a capture that wasn't running. The same
goes for one that starts capturing later for someone else's reasons: the
picture appears when the robot says so.

Your own choice wins over both. A preview you started shows before the camera
has reported catching up — it has to, since watching is what makes it happen —
and one you paused stays hidden even while the camera keeps capturing for
others. Neither is forgotten when the camera list refreshes.

## Try it without a camera

The dev server in this repository declares `BB.Camera.Synthetic` — a real
`bb_camera` driver producing a moving test pattern, no hardware — on its robot,
and previews it through exactly the production path. From a checkout of the
Beam Bots workspace, with `bb`, `bb_camera` and `bb_camera_webrtc` beside
`bb_liveview`:

```sh
cd bb_liveview
BB_VERSION=local mix deps.get
mix assets.setup        # first run only, fetches npm packages
mix assets.build
BB_VERSION=local mix phx.server
```

Then open <http://localhost:4000>, choose the Cameras tab and press **Start
capturing** on `head_camera`.

The synthetic camera belongs in a robot like any other driver:

```elixir
topology do
  link :base_link do
    sensor :head_camera, {BB.Camera.Synthetic, width: 640, height: 480, clock: {:rate, 30}}
  end
end
```

`clock: :external` plus `BB.Camera.Synthetic.capture_frame/2` gives a camera
that produces a frame exactly when a test says so, which is how to test
anything downstream of a camera without sleeping.

## Use a real USB camera on Debian

With `bb_camera` and a V4L driver installed, point a sensor at the device.
First confirm the kernel and your user can see it:

```sh
sudo apt install v4l-utils
v4l2-ctl --list-devices
v4l2-ctl --list-formats-ext -d /dev/video0
id -nG | grep -q video || sudo usermod -aG video "$USER"   # log out and back in
```

Then declare it:

```elixir
topology do
  link :base_link do
    sensor :head_camera, {BB.Camera.V4L, device: "/dev/video0", width: 640, height: 480}
  end
end
```

Start the robot and the dashboard, and the camera appears with no further
configuration.

## Supplying cameras another way

Everything the dashboard knows about cameras goes through the
`BB.LiveView.Camera` behaviour, chosen with:

```elixir
config :bb_liveview, :camera, MyCameraSource
```

Leave it unset and it resolves to `BB.LiveView.Camera.BBCamera`, which uses
`bb_camera` and `bb_camera_webrtc`. This repository's tests point it at
`BB.LiveView.SyntheticCamera`, a double that plays the camera's half of the
signalling under the test's control.
