<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Preview cameras on the dashboard

The dashboard finds a robot's cameras by itself and previews them. There is
nothing to wire up: mount `bb_dashboard` as usual and any camera the robot
declares appears in the Cameras widget.

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

`BB.Camera` (from the `bb_camera` package) is what makes it a camera rather
than just a sensor. `bb_liveview` does not depend on `bb_camera`: with the
package absent there are no cameras to find, the widget says so, and nothing
else about the dashboard changes.

## How frames reach the browser

**Not over the LiveView socket.** Video never travels through PubSub or through
LiveView events — the only camera traffic on PubSub is lifecycle events
(capture started, capture ended, settings applied or rejected), which the
dashboard uses to keep the camera list honest.

Each preview is an `<img>` pointing at `BB.LiveView.Plugs.CameraStream`, which
`bb_dashboard/2` mounts at `<your mount path>/__bb_camera__/:camera/mjpeg`. The
browser opens an ordinary HTTP connection and gets
`multipart/x-mixed-replace` — MJPEG. One request is one consumer of the
camera's single shared capture; the camera starts capturing when the first
consumer arrives and stops when the last one leaves.

Pausing a preview removes the `<img>`, which closes the connection, which drops
the consumer. Closing the browser tab does the same thing without being asked.

### Authentication

The camera route is defined **inside the same scope as the dashboard**, so
whatever pipeline guards the dashboard guards the stream:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_admin]
  bb_dashboard "/robot", robot: MyRobot
end
```

Here `/admin/robot/__bb_camera__/head_camera/mjpeg` goes through
`:require_admin` exactly as the dashboard does. The reverse is also true: if
the dashboard is public, the stream is public. **A stream URL is not a
credential** — it is guessable from the camera's name, and it must not be
treated as a secret.

### Why MJPEG, and where Membrane isn't

MJPEG is the smallest thing that works: every browser renders it in an `<img>`
with no JavaScript, and the camera already produces whole JPEG frames. The
preview path is camera → HTTP response, with **no Membrane pipeline in it** —
a stream of complete JPEGs gains nothing from one. `bb_camera` ships
`BB.Camera.Membrane.Source` for the transports that will need real muxing
(fragmented MP4, WebRTC); those belong on top of it, not on top of this.

### Backpressure

The route asks for one frame at a time and only asks for the next once the
current one has been written, and the camera hub holds exactly one latest
frame. A browser on a slow link therefore *skips* frames; it never makes the
camera side accumulate them. (The web server still buffers whatever it has
accepted for the socket — what's guaranteed is that a stalled reader can't
grow a queue behind the camera.)

## Options

```elixir
bb_dashboard "/robot",
  robot: MyRobot,
  camera_stream: [first_frame_timeout: 5_000, frame_timeout: 10_000]
```

* `:first_frame_timeout` — how long a camera has to produce its first frame.
  The response status is decided *before* any bytes are sent, so a camera that
  is declared but offline, or alive but producing nothing, answers 503 instead
  of a 200 that hangs.
* `:frame_timeout` — how long a stalled camera is given mid-stream before the
  response is ended. A camera that disappears ends the response; it never
  leaves the request hanging.

## Try it without a camera

The dev server in this repository runs a synthetic camera — real JPEG frames,
no hardware — through exactly the production path. From a checkout of
`bb_liveview` (Debian, Elixir and Erlang per `.tool-versions`):

```sh
cd bb_liveview
mix deps.get
mix assets.setup        # first run only, fetches npm packages
mix assets.build
mix phx.server
```

Then open <http://localhost:4000>. The Cameras widget shows two cameras:
`head_camera`, previewing at 10 fps, and `gripper_camera`, which is declared
but not running — the offline state a dashboard should show rather than hiding
a camera that ought to be there.

To see the raw stream:

```sh
curl -N http://localhost:4000/__bb_camera__/head_camera/mjpeg | head -c 200 | xxd | head
```

The synthetic implementation is `BB.LiveView.SyntheticCamera`, selected in
`config/dev.exs` with:

```elixir
config :bb_liveview, :camera, BB.LiveView.SyntheticCamera
```

That key is the seam the whole camera path hangs off. Leave it unset in a real
application and it resolves to `bb_camera`.

### With `bb_camera` installed

Once the package is a dependency of your own application, the synthetic camera
is a real driver and belongs in the robot rather than in config:

```elixir
topology do
  link :base_link do
    sensor :head_camera, {BB.Camera.Synthetic, clock: {:rate, 10}}
  end
end
```

Everything else is identical — the dashboard discovers it, previews it, and
stops its capture when the last browser goes away. `clock: :external` plus
`BB.Camera.Synthetic.capture_frame/2` gives a camera that produces a frame
exactly when a test says so, which is how to test anything downstream of a
camera without sleeping.

## Use a real USB camera on Debian

With `bb_camera` and a V4L driver installed, point a sensor at the device.
First confirm the kernel and your user can see it:

```sh
sudo apt install v4l-utils
v4l2-ctl --list-devices
v4l2-ctl --list-formats-ext -d /dev/video0 | grep -A3 MJPG
id -nG | grep -q video || sudo usermod -aG video "$USER"   # log out and back in
```

The `MJPG` line matters: the preview carries JPEG, so a camera that only offers
`YUYV` needs the driver to encode, which costs CPU. Most laptop and USB
webcams offer MJPG natively.

Then declare it:

```elixir
topology do
  link :base_link do
    sensor :head_camera, {BB.Camera.V4L, device: "/dev/video0", width: 640, height: 480}
  end
end
```

Start the robot and the dashboard, and the camera appears beside the synthetic
one with no further configuration.
