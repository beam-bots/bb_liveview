# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.SyntheticCamera do
  @moduledoc """
  A camera implementation with no camera and no WebRTC, for testing the
  dashboard's side of the `BB.LiveView.Camera` seam.

      config :bb_liveview, :camera, BB.LiveView.SyntheticCamera

  Cameras are whatever it was started with. Watching one hands the test the
  stream, and the test plays the camera's half of the signalling, so it can
  see exactly what the dashboard asked for and answer it, with nothing to wait
  for:

    * `{:synthetic_camera, {:watching, camera, stream, opts}}` is sent to the
      reporting process when the dashboard starts watching `camera`;
    * `to_browser/2` sends a signalling message from the "camera" to the
      dashboard, as a WebRTC sink would;
    * `{:synthetic_camera, {:from_browser, camera, message}}` reports each
      message the dashboard passes back;
    * `end_stream/1` ends a stream, as a camera stopping would;
    * `{:synthetic_camera, {:unwatched, camera, stream}}` reports the
      dashboard letting go.

  `to_browser/2` and `end_stream/1` send straight from the test to the
  watching process, so anything the test asks of that process afterwards is
  answered with the message already handled.
  """

  use GenServer

  @behaviour BB.LiveView.Camera

  @doc """
  Starts the synthetic camera.

  ## Options

  * `:cameras` — required, a list of camera specifications. Each is a map of
    `:robot`, `:name`, and optionally `:path`, `:attached_to`, `:status`
    (`:capturing | :running | :declared`) and `:stream`.
  * `:available?` — whether a camera package is installed, `true` by
    default; `false` stands in for an application without `bb_camera`.
  * `:webrtc?` — whether streaming is available, `true` by default; `false`
    stands in for an application without `bb_camera_webrtc`.
  * `:report_to` — the process to send events to.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @typedoc "A stream: the watch the dashboard holds, and what the test is handed."
  @type stream :: %{camera: atom, ref: reference, report_to: pid | nil, viewer: pid}

  @doc "Ends a stream, as a camera stopping would."
  @spec end_stream(stream) :: :ok
  def end_stream(stream) do
    send(stream.viewer, {__MODULE__, stream.ref, :ended})
    :ok
  end

  @doc "Changes a camera's status, standing in for a robot starting or a sensor dying."
  @spec set_status(atom, :capturing | :running | :declared) :: :ok
  def set_status(camera, status) do
    GenServer.call(__MODULE__, {:set_status, camera, status})
  end

  @doc "Sends a signalling message from the camera's side of `stream` to the dashboard."
  @spec to_browser(stream, map) :: :ok
  def to_browser(stream, message) do
    send(stream.viewer, {__MODULE__, stream.ref, {:signal, message}})
    :ok
  end

  @impl BB.LiveView.Camera
  def available? do
    GenServer.call(__MODULE__, :available?)
  end

  @impl BB.LiveView.Camera
  def discover(robot_module) do
    GenServer.call(__MODULE__, {:discover, robot_module})
  end

  @impl BB.LiveView.Camera
  def signal(stream, message) do
    report(stream.report_to, {:from_browser, stream.camera, message})
  end

  @impl BB.LiveView.Camera
  def stream_event(%{ref: ref}, {__MODULE__, ref, event}), do: event
  def stream_event(_stream, _message), do: nil

  @impl BB.LiveView.Camera
  def stream_message?({__MODULE__, ref, _event}) when is_reference(ref), do: true
  def stream_message?(_message), do: false

  @impl BB.LiveView.Camera
  def unwatch(stream) do
    report(stream.report_to, {:unwatched, stream.camera, stream})
  end

  @impl BB.LiveView.Camera
  def watch(robot_module, camera_name, opts) do
    GenServer.call(__MODULE__, {:watch, robot_module, camera_name, self(), opts})
  end

  @impl BB.LiveView.Camera
  def webrtc_available? do
    GenServer.call(__MODULE__, :webrtc?)
  end

  @impl GenServer
  def init(opts) do
    cameras =
      opts
      |> Keyword.fetch!(:cameras)
      |> Map.new(&{&1.name, build_camera(&1)})

    {:ok,
     %{
       available?: Keyword.get(opts, :available?, true),
       cameras: cameras,
       report_to: Keyword.get(opts, :report_to),
       webrtc?: Keyword.get(opts, :webrtc?, true)
     }}
  end

  @impl GenServer
  def handle_call(:available?, _from, state) do
    {:reply, state.available?, state}
  end

  def handle_call({:discover, robot_module}, _from, state) do
    infos =
      state.cameras
      |> Map.values()
      |> Enum.filter(&(&1.robot == robot_module))
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&info/1)

    {:reply, infos, state}
  end

  def handle_call({:set_status, name, status}, _from, state) do
    {:reply, :ok, put_in(state, [:cameras, name, :status], status)}
  end

  def handle_call({:watch, robot, name, viewer, opts}, _from, state) do
    case Map.get(state.cameras, name) do
      %{robot: ^robot, status: status} when status != :declared ->
        stream = %{camera: name, ref: make_ref(), report_to: state.report_to, viewer: viewer}
        report(state.report_to, {:watching, name, stream, opts})
        {:reply, {:ok, stream}, state}

      _missing_or_offline ->
        {:reply, {:error, :unknown_camera}, state}
    end
  end

  def handle_call(:webrtc?, _from, state) do
    {:reply, state.webrtc?, state}
  end

  defp build_camera(spec) do
    name = Map.fetch!(spec, :name)

    %{
      robot: Map.fetch!(spec, :robot),
      name: name,
      path: Map.get(spec, :path, [:sensor, name]),
      attached_to: Map.get(spec, :attached_to, :robot),
      status: Map.get(spec, :status, :running),
      stream: Map.get(spec, :stream, default_stream())
    }
  end

  defp default_stream, do: %{format: {:raw, :I420}, width: 160, height: 120, frame_rate: 10.0}

  # `options` and `metadata` are deliberately *not* in `BB.Camera.Info` — the
  # real contract keeps device paths and credentials away from consumers at
  # source. They are returned here anyway so the dashboard's own sanitising can
  # be tested: anything it doesn't explicitly ask for must not reach a browser.
  defp info(camera) do
    %{
      options: [device: "/dev/video0", password: "hunter2"],
      metadata: %{serial: "SN-0001"},
      robot: camera.robot,
      name: camera.name,
      path: camera.path,
      topic: camera.path,
      module: __MODULE__,
      attached_to: camera.attached_to,
      stream_info: camera.stream,
      status: camera.status,
      pid: if(camera.status == :declared, do: nil, else: self())
    }
  end

  defp report(nil, _event), do: :ok

  defp report(pid, event) do
    send(pid, {:synthetic_camera, event})
    :ok
  end
end
