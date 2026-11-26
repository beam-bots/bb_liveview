# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Camera do
  @moduledoc """
  The slice of `bb_camera` and `bb_camera_webrtc` the dashboard consumes, and
  the lookups built on it.

  A camera is an ordinary `BB.Sensor` callback module that also implements
  `BB.Camera`. Video never travels over BB PubSub or the LiveView socket —
  PubSub carries only lifecycle events (capture begin/end) and periodic
  capture telemetry, and the socket carries only the WebRTC signalling that
  sets up a stream. The pixels go from the robot to the browser over WebRTC.

  ## Watching

  `watch/3` starts streaming one camera to one browser on behalf of the calling
  process, and returns a `t:watch/0`. The stream then sends the caller
  messages whose shape is the implementation's business. Pass each one to
  `stream_message?/1` to learn whether it belongs to a stream, and to
  `stream_event/2` to learn what it means for a given watch:

    * `{:signal, message}` — signalling bound for the browser, `message`
      being a JSON-shaped map (`%{"type" => "sdp_offer", "data" => ...}`);
    * `:ended` — the camera stopped, the browser's connection failed, or the
      pipeline went down. Watching again starts a fresh stream;
    * `nil` — the message belongs to some other watch.

  `signal/2` hands the browser's replies back, and `unwatch/1` stops a stream,
  as does the caller exiting.

  ## Optional dependencies

  Neither `bb_camera` nor `bb_camera_webrtc` is required. Every call goes
  through `implementation/0`, which is `BB.LiveView.Camera.BBCamera` by
  default and reaches both packages only via `apply/3` behind
  `Code.ensure_loaded?/1`. With no camera package installed `discover/1`
  answers `[]` for every robot, which is the whole truth: a robot cannot
  declare a camera without the package, because `use BB.Camera` would not
  compile. With `bb_camera` but no `bb_camera_webrtc` cameras are listed but
  not previewable.

  Point the seam elsewhere to supply a different source — the tests drive the
  dashboard with a double this way:

      config :bb_liveview, :camera, MyCameraSource
  """

  @default_implementation BB.LiveView.Camera.BBCamera

  @typedoc """
  What the dashboard is allowed to know about a camera.

  Narrower than `BB.Camera.Info` on purpose. `Info` already omits the DSL
  options a camera was declared with — device paths, URLs, credentials — and
  this drops the driver-supplied `metadata` map too, so nothing a driver author
  chose to stash can reach a browser by being rendered accidentally.
  """
  @type camera :: %{
          name: atom,
          path: [atom],
          topic: [atom],
          module: module,
          attached_to: {:link, atom} | {:joint, atom} | :robot,
          status: :capturing | :running | :declared,
          stream: stream | nil,
          previewable?: boolean
        }

  @type stream :: %{
          format: atom | {:raw, atom},
          width: pos_integer,
          height: pos_integer,
          frame_rate: float | nil
        }

  @typedoc "A stream being watched. Opaque: only the implementation looks inside."
  @type watch :: term

  @typedoc "What a stream's message means for one watch."
  @type stream_event :: {:signal, map} | :ended | nil

  @doc "Whether a camera implementation is installed."
  @callback available?() :: boolean

  @doc "Every camera declared by a robot, running or not."
  @callback discover(robot :: module) :: [struct]

  @doc "Hands a validated signalling message from the browser to a stream."
  @callback signal(watch, message :: map) :: :ok

  @doc "What `message`, received by the watching process, means for `watch`."
  @callback stream_event(watch, message :: term) :: stream_event

  @doc "Whether `message`, received by the watching process, came from a stream."
  @callback stream_message?(message :: term) :: boolean

  @doc """
  Stops a stream started by `watch/3` from the same process. Afterwards the
  caller receives nothing more about it. Harmless on one that has ended.
  """
  @callback unwatch(watch) :: :ok

  @doc """
  Starts streaming `camera` to a browser on behalf of the calling process,
  which becomes the stream's signalling peer, until it unwatches or exits.
  """
  @callback watch(robot :: module, camera :: atom, opts :: keyword) ::
              {:ok, watch} | {:error, term}

  @doc "Whether cameras can be streamed to a browser."
  @callback webrtc_available?() :: boolean

  @doc """
  Whether a camera implementation is installed.

  `false` means no camera package, which the dashboard renders as an
  explanation rather than an error.
  """
  @spec available?() :: boolean
  def available? do
    implementation().available?()
  end

  @doc """
  Every camera declared by `robot_module`, sanitised for display.

  Answers `[]` for anything that isn't a robot, and for every robot when no
  camera package is installed.
  """
  @spec discover(module) :: [camera]
  def discover(robot_module) when is_atom(robot_module) do
    if available?() and robot?(robot_module) do
      webrtc? = webrtc_available?()

      robot_module
      |> implementation().discover()
      |> Enum.map(&describe(&1, webrtc?))
    else
      []
    end
  end

  def discover(_robot_module), do: []

  @doc "The module implementing the camera contract."
  @spec implementation() :: module
  def implementation do
    Application.get_env(:bb_liveview, :camera, @default_implementation)
  end

  @doc "A human-readable name for a camera, including where it is attached."
  @spec label(camera) :: String.t()
  def label(%{name: name, attached_to: {kind, where}}),
    do: "#{humanise(name)} (#{kind} #{humanise(where)})"

  def label(%{name: name}), do: humanise(name)

  @doc """
  Hands a signalling message from the browser to a stream.

  Only an SDP answer or an ICE candidate is passed on. Anything else — the
  `null` or empty candidate a browser sends when it has finished gathering, or
  a message that isn't signalling at all — is dropped here rather than handed
  to a WebRTC sink that would crash on it.
  """
  @spec signal(watch, map) :: :ok
  def signal(watch, %{"type" => "sdp_answer", "data" => %{"sdp" => _} = data}) do
    implementation().signal(watch, %{"type" => "sdp_answer", "data" => data})
  end

  def signal(watch, %{
        "type" => "ice_candidate",
        "data" => %{"candidate" => candidate} = data
      })
      when is_binary(candidate) and candidate != "" do
    implementation().signal(watch, %{"type" => "ice_candidate", "data" => data})
  end

  def signal(_watch, _message), do: :ok

  @doc "What `message`, received by the watching process, means for `watch`."
  @spec stream_event(watch, term) :: stream_event
  def stream_event(watch, message) do
    implementation().stream_event(watch, message)
  end

  @doc """
  Whether `message`, received by the watching process, came from a camera
  stream — so a LiveView can pass it on without knowing what it looks like.
  """
  @spec stream_message?(term) :: boolean
  def stream_message?(message) do
    implementation().stream_message?(message)
  end

  @doc """
  Stops a stream. Afterwards the caller receives nothing more about it.
  Harmless on one that has already ended.
  """
  @spec unwatch(watch) :: :ok
  def unwatch(watch) do
    implementation().unwatch(watch)
  end

  @doc """
  Starts streaming `camera_name` to a browser, on behalf of the calling
  process. See "Watching" above.

  ## Options

    * `:ice_servers` — STUN and TURN servers for browsers that can't reach the
      robot directly. None by default.
  """
  @spec watch(module, atom, keyword) :: {:ok, watch} | {:error, term}
  def watch(robot_module, camera_name, opts \\ []) do
    if webrtc_available?() do
      implementation().watch(robot_module, camera_name, opts)
    else
      {:error, :no_webrtc}
    end
  end

  @doc """
  Whether cameras can be streamed to a browser — that is, whether
  `bb_camera_webrtc` is installed.
  """
  @spec webrtc_available?() :: boolean
  def webrtc_available? do
    available?() and implementation().webrtc_available?()
  end

  defp describe(info, webrtc?) do
    stream = describe_stream(info.stream_info)

    %{
      name: info.name,
      path: info.path,
      topic: info.topic,
      module: info.module,
      attached_to: info.attached_to,
      status: info.status,
      stream: stream,
      previewable?: webrtc? and match?(%{format: {:raw, :I420}}, stream)
    }
  end

  defp describe_stream(nil), do: nil

  defp describe_stream(stream_info) do
    %{
      format: stream_info.format,
      width: stream_info.width,
      height: stream_info.height,
      frame_rate: stream_info.frame_rate
    }
  end

  defp humanise(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp robot?(robot_module) do
    Code.ensure_loaded?(robot_module) and function_exported?(robot_module, :robot, 0)
  end
end
