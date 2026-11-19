# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Camera do
  @moduledoc """
  The slice of `bb_camera` the dashboard consumes, and the lookups built on it.

  A camera is an ordinary `BB.Sensor` callback module that also implements
  `BB.Camera`. Video never travels over BB PubSub — PubSub carries only
  lifecycle events (capture begin/end) and periodic capture telemetry — so the
  dashboard gets pixels solely through the bounded, demand-driven media session
  described below. `BB.LiveView.Plugs.CameraStream` turns one session into one
  MJPEG response.

  ## Demand

  `open/3` delivers nothing by itself. Each `next/2` returns one frame
  *strictly newer* than the one that session last returned, so a reader loop
  runs at the camera's capture rate rather than at CPU speed, and a reader that
  stops asking costs the camera nothing. The hub holds a single latest frame
  per camera, so a slow consumer loses intermediate frames rather than
  accumulating them.

  ## Optional dependency

  `bb_camera` is not a dependency of `bb_liveview`. Every call goes through
  `implementation/0`, which is `BB.LiveView.Camera.BBCamera` by default and
  reaches `bb_camera` only via `apply/3` behind `Code.ensure_loaded?/1`. With
  no camera package installed `discover/1` answers `[]` for every robot, which
  is the whole truth: a robot cannot declare a camera without the package,
  because `use BB.Camera` would not compile.

  Point the seam elsewhere to supply a different source — the dev server runs a
  synthetic camera this way, and the tests drive it with a gated double:

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

  @type session :: term

  @doc "Whether a camera implementation is installed."
  @callback available?() :: boolean

  @doc "Closes a media session. Must not raise, whatever state the camera is in."
  @callback close(session) :: :ok

  @doc "Every camera declared by a robot, running or not."
  @callback discover(robot :: module) :: [struct]

  @doc "Waits for a frame newer than the last one this session returned."
  @callback next(session, timeout) :: {:ok, struct} | {:error, term}

  @doc "Opens one consumer on the camera's shared capture."
  @callback open(robot :: module, camera :: atom, opts :: keyword) ::
              {:ok, session} | {:error, term}

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
  Closes a media session.

  Swallows a failing close. This runs in the cleanup path of an HTTP response
  that has usually already been written, and a camera that died mid-stream is
  exactly when close is most likely to be unhappy — letting it raise there
  would replace a successful response with a 500.
  """
  @spec close(session) :: :ok
  def close(session) do
    implementation().close(session)
  catch
    _kind, _reason -> :ok
  end

  @doc """
  Every camera declared by `robot_module`, sanitised for display.

  Answers `[]` for anything that isn't a robot, and for every robot when no
  camera package is installed.
  """
  @spec discover(module) :: [camera]
  def discover(robot_module) when is_atom(robot_module) do
    if available?() and robot?(robot_module) do
      robot_module
      |> implementation().discover()
      |> Enum.map(&describe/1)
    else
      []
    end
  end

  def discover(_robot_module), do: []

  @doc """
  Resolves a camera name taken from a request path.

  Compares the string against the names already discovered rather than
  converting it to an atom, so an unknown name is a miss instead of a new entry
  in the atom table.
  """
  @spec fetch(module, String.t()) :: {:ok, camera} | :error
  def fetch(robot_module, name) when is_binary(name) do
    robot_module
    |> discover()
    |> Enum.find(&(Atom.to_string(&1.name) == name))
    |> case do
      nil -> :error
      camera -> {:ok, camera}
    end
  end

  def fetch(_robot_module, _name), do: :error

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
  Waits for a frame newer than the last one this session returned.

  Any error is a safe signal to stop streaming to this consumer: the camera
  stopped, failed, died, or produced nothing inside the timeout.
  """
  @spec next(session, timeout) :: {:ok, struct} | {:error, term}
  def next(session, timeout) do
    implementation().next(session, timeout)
  end

  @doc """
  Opens one consumer on a camera's shared capture.

  The hub monitors the owner, so a browser disconnecting — or the connection
  process crashing — releases the consumer and lets the capture stop. Asserting
  `format: :jpeg` makes a camera that cannot be previewed fail here, loudly,
  rather than hand back bytes the browser can't render.
  """
  @spec open(module, atom, keyword) :: {:ok, session} | {:error, term}
  def open(robot_module, camera_name, opts \\ []) do
    if available?() do
      implementation().open(robot_module, camera_name, opts)
    else
      {:error, :no_camera_implementation}
    end
  end

  @doc """
  The path a browser fetches an MJPEG preview from.

  Built from the path the dashboard is actually mounted at, so a dashboard
  under `/admin/arm` streams from `/admin/arm/__bb_camera__/…` without this
  library knowing the host, the scheme or the mount point.
  """
  @spec stream_path(String.t(), camera | atom) :: String.t()
  def stream_path(base_path, %{name: name}), do: stream_path(base_path, name)

  def stream_path(base_path, name) when is_atom(name) do
    Path.join([base_path, "__bb_camera__", Atom.to_string(name), "mjpeg"])
  end

  defp describe(info) do
    stream = describe_stream(info.stream_info)

    %{
      name: info.name,
      path: info.path,
      topic: info.topic,
      module: info.module,
      attached_to: info.attached_to,
      status: info.status,
      stream: stream,
      previewable?: match?(%{format: :jpeg}, stream)
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
