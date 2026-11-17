<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# camera_spike

A whole robot, a dashboard and a camera, wired together with the real
packages — `bb`, `bb_camera`, `bb_camera_v4l` and `bb_liveview`, all resolved
from the sibling checkouts in this workspace. Nothing here is a test double.

It exists for two reasons: to be a thing you can start and look at, and to hold
the integration tests that prove the dashboard's camera path is wired to the
packages it claims to be. `bb_liveview`'s own suite tests the dashboard against
a stand-in; this tests it against `bb_camera`.

## Start it

From this directory:

```sh
BB_VERSION=local mix deps.get
PORT=4100 BB_VERSION=local MIX_ENV=prod mix run --no-halt
```

Then open:

* dashboard — <http://localhost:4100/robot>
* raw stream — <http://localhost:4100/robot/__bb_camera__/eye/mjpeg>

The startup log prints both, along with the camera it was built with.

```sh
curl -N --max-time 3 http://localhost:4100/robot/__bb_camera__/eye/mjpeg | head -c 64 | xxd
```

`MIX_ENV=prod` is not ceremony: `bb_liveview` starts its *own* dev server when
it is compiled in `:dev`, which would bind port 4000 and start a second robot
alongside this one. In `:prod` it is an ordinary library.

`PORT` picks the port — 4001 by default, chosen to stay clear of a `bb_liveview`
dev server on 4000. `BIND=0.0.0.0` makes it reachable from another machine,
which is what you need if the browser isn't on the robot.

## Point it at a real camera

The camera is declared in `lib/camera_spike/robot.ex` like any other sensor.
Which driver it is comes from `config/config.exs`, which reads the environment,
so switching is a matter of exporting a variable and starting again — Mix
notices the change and recompiles the robot.

| Variable | Default | Meaning |
|---|---|---|
| `CAMERA_DEVICE` | unset | A V4L2 device node, e.g. `/dev/video0`. Switches to `BB.Camera.V4L` |
| `CAMERA_LAVFI` | unset | An ffmpeg synthetic source, e.g. `testsrc2`. Also `BB.Camera.V4L`, no hardware |
| `CAMERA_WIDTH` | `640` | Width to ask for |
| `CAMERA_HEIGHT` | `480` | Height to ask for |
| `CAMERA_FPS` | `10` | Frame rate to ask for |
| `PORT` | `4001` | HTTP port |
| `BIND` | `127.0.0.1` | Address to bind |

### Synthetic, no hardware, no ffmpeg (the default)

```sh
PORT=4100 BB_VERSION=local MIX_ENV=prod mix run --no-halt
```

`BB.Camera.Synthetic` emits a short cycle of real 160×120 JPEGs. It reports the
size it actually produced rather than the size you asked for, which is the same
thing a real camera does when it negotiates something different.

### A real webcam on Debian

```sh
sudo apt install v4l-utils ffmpeg
v4l2-ctl --list-devices
v4l2-ctl --list-formats-ext -d /dev/video0 | grep -A3 MJPG
id -nG | grep -q video || sudo usermod -aG video "$USER"   # then log out and back in

CAMERA_DEVICE=/dev/video0 CAMERA_WIDTH=1280 CAMERA_HEIGHT=720 CAMERA_FPS=30 \
  PORT=4100 BB_VERSION=local MIX_ENV=prod mix run --no-halt
```

The `MJPG` line matters. The preview carries JPEG, and `BB.Camera.V4L` asks the
device for MJPEG and copies the packets through without decoding — no
transcode, almost no CPU, whatever the resolution. A camera with no MJPEG mode
still works by naming the format it has (`input_format: :yuyv422` in the DSL),
but then ffmpeg encodes every frame and you pay for it.

### ffmpeg's synthetic source — the real driver, no camera

```sh
CAMERA_LAVFI=testsrc2 PORT=4100 BB_VERSION=local MIX_ENV=prod mix run --no-halt
```

This runs the whole V4L path — a real ffmpeg process, a real pipe, real JPEG
framing — against a generated image. It is how you tell a broken camera from a
broken setup.

## Test it

```sh
BB_VERSION=local mix test                    # no camera, no ffmpeg needed
BB_VERSION=local mix test --include ffmpeg   # also drives ffmpeg via lavfi
```

The default run uses `BB.Camera.Synthetic` with `clock: :external`, so a frame
exists exactly when a test asks for one and nothing waits on a clock. The
`:ffmpeg` tests use `BB.Camera.V4L` against `lavfi:"testsrc2"` — a real ffmpeg,
no hardware — and are excluded by default because not every machine has ffmpeg.

What the tests cover:

* `BB.Camera.discover/1` finds the camera declared in the robot's DSL, and what
  reaches the dashboard carries none of the driver's options.
* A name from a URL resolves only to a camera that exists, and never becomes a
  new atom.
* `BB.Camera.Media` hands over real JPEG, strictly newer each time.
* The MJPEG route, reached through this app's own endpoint and router: 200 with
  multipart JPEG, 404 for an unknown camera, and 503 — decided before any byte
  is written — for a camera that produces nothing.
* The dashboard renders the camera and builds its preview URL from the path the
  dashboard is mounted at.
* The same Plug, fed by the real V4L driver through ffmpeg.

## What this is not

It is not a template for an application. There is no authentication, the
endpoint's secret is a constant in the repo, and `check_origin` is off. The
camera stream is as protected as the pipeline in front of it, and this one has
nothing in front of it.
