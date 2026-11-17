# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.SyntheticCamera do
  @moduledoc """
  A camera implementation with no camera, standing in for `bb_camera` while the
  real package is being built, and for hardware the machine doesn't have.

  It implements `BB.LiveView.Camera` — the same seam the real
  `BB.LiveView.Camera.BBCamera` plugs into — so the dashboard, the HTTP route
  and the browser exercise exactly the production path. Only the source of the
  bytes is synthetic.

      config :bb_liveview, :camera, BB.LiveView.SyntheticCamera

  ## Clocks

  `clock: {:rate, hertz}` emits a frame on a timer, which is what the dev
  server uses to produce a moving picture.

  `clock: :external` emits only when a test calls `capture/1`, which is what
  makes the tests deterministic: a frame exists exactly when the test says so,
  so nothing has to wait a plausible-looking number of milliseconds.

  ## Demand, and what a slow consumer loses

  The hub holds one latest frame per camera. Frames captured while nobody is
  asking overwrite it, and `next/2` only ever answers with a frame *newer* than
  the one that session last received. A consumer that reads slowly therefore
  skips frames and never accumulates them — which is the property the HTTP
  route depends on, so it is reproduced here faithfully rather than
  approximated.

  Not compiled into released builds: `elixirc_paths/1` only picks `test/support`
  up in `:dev` and `:test`.
  """

  use GenServer

  @behaviour BB.LiveView.Camera

  alias BB.LiveView.SyntheticCamera.Frames

  defstruct [:camera, :id, :owner, :ref, :robot, :server]

  @type t :: %__MODULE__{}

  @doc """
  Starts the synthetic camera hub.

  ## Options

  * `:cameras` — required, a list of camera specifications. Each is a map of
    `:robot`, `:name`, and optionally `:path`, `:attached_to`, `:status`
    (`:capturing | :running | :declared`) and `:stream`.
  * `:clock` — `:external` (default) or `{:rate, hertz}`.
  * `:name` — process name, `#{inspect(__MODULE__)}` by default.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Captures one frame on `camera`, returning once every waiting consumer has it."
  @spec capture(atom, atom) :: :ok
  def capture(server \\ __MODULE__, camera) do
    GenServer.call(server, {:capture, camera})
  end

  @doc """
  Ends capture on `camera`, as a driver stopping cleanly would.

  Every waiting consumer is answered with `{:error, :end_of_capture}` and every
  later request fails the same way, so a test can end an HTTP stream without
  waiting for a timeout.
  """
  @spec stop_capture(atom, atom) :: :ok
  def stop_capture(server \\ __MODULE__, camera) do
    GenServer.call(server, {:stop_capture, camera})
  end

  @doc "How many consumers are open on `camera`."
  @spec consumer_count(atom, atom) :: non_neg_integer
  def consumer_count(server \\ __MODULE__, camera) do
    GenServer.call(server, {:consumer_count, camera})
  end

  @doc """
  Sends hub events to `pid`, so a test can wait for one instead of guessing.

  Events are `{:synthetic_camera, {:capture_started, camera}}`,
  `{:synthetic_camera, {:capture_stopped, camera}}` and
  `{:synthetic_camera, {:consumer_released, camera, reason}}`.
  """
  @spec watch(atom, pid) :: :ok
  def watch(server \\ __MODULE__, pid) do
    GenServer.call(server, {:watch, pid})
  end

  @doc "Changes a camera's status, standing in for a robot starting or a sensor dying."
  @spec set_status(atom, atom, :capturing | :running | :declared) :: :ok
  def set_status(server \\ __MODULE__, camera, status) do
    GenServer.call(server, {:set_status, camera, status})
  end

  @impl BB.LiveView.Camera
  def available?, do: true

  @impl BB.LiveView.Camera
  def close(%__MODULE__{} = session) do
    GenServer.call(session.server, {:close, session.id, :closed})
  end

  @impl BB.LiveView.Camera
  def discover(robot_module) do
    GenServer.call(__MODULE__, {:discover, robot_module})
  end

  @impl BB.LiveView.Camera
  def next(%__MODULE__{} = session, timeout) do
    :ok = GenServer.call(session.server, {:request, session.id})
    ref = session.ref

    receive do
      {:synthetic_camera_frame, ^ref, result} -> result
    after
      timeout ->
        GenServer.call(session.server, {:cancel_request, session.id})
        flush(ref)
        {:error, :timeout}
    end
  end

  @impl BB.LiveView.Camera
  def open(robot_module, camera_name, opts) do
    owner = Keyword.get(opts, :owner, self())
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:open, robot_module, camera_name, opts, owner, server})
  end

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, :external)

    cameras =
      opts
      |> Keyword.fetch!(:cameras)
      |> Map.new(&{&1.name, build_camera(&1)})

    state = %{cameras: cameras, sessions: %{}, watchers: [], clock: clock, next_id: 1}

    {:ok, schedule_tick(state)}
  end

  @impl GenServer
  def handle_call({:cancel_request, id}, _from, state) do
    {:reply, :ok, update_session(state, id, &%{&1 | demand?: false})}
  end

  def handle_call({:capture, name}, _from, state) do
    {:reply, :ok, capture_frame(state, name)}
  end

  def handle_call({:close, id, reason}, _from, state) do
    {:reply, :ok, release(state, id, reason)}
  end

  def handle_call({:consumer_count, name}, _from, state) do
    {:reply, count_consumers(state, name), state}
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

  def handle_call({:open, robot, name, opts, owner, server}, _from, state) do
    case Map.get(state.cameras, name) do
      nil -> {:reply, {:error, :unknown_camera}, state}
      %{robot: other} when other != robot -> {:reply, {:error, :unknown_camera}, state}
      %{status: :declared} -> {:reply, {:error, :not_running}, state}
      camera -> open_session(state, camera, opts, owner, server)
    end
  end

  def handle_call({:request, id}, _from, state) do
    state = notify(state, {:demand, camera_of(state, id)})
    {:reply, :ok, demand(state, id)}
  end

  def handle_call({:stop_capture, name}, _from, state) do
    state =
      state.sessions
      |> Enum.filter(fn {_id, session} -> session.camera == name end)
      |> Enum.reduce(state, fn {id, session}, state ->
        send(session.owner, {:synthetic_camera_frame, session.ref, {:error, :end_of_capture}})
        put_in(state.sessions[id], %{session | demand?: false})
      end)

    {:reply, :ok, put_in(state, [:cameras, name, :ended?], true)}
  end

  def handle_call({:set_status, name, status}, _from, state) do
    {:reply, :ok, put_in(state, [:cameras, name, :status], status)}
  end

  def handle_call({:watch, pid}, _from, state) do
    {:reply, :ok, %{state | watchers: [pid | state.watchers]}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      state.sessions
      |> Enum.filter(fn {_id, session} -> session.owner == pid end)
      |> Enum.reduce(state, fn {id, _session}, state -> release(state, id, :owner_down) end)

    {:noreply, state}
  end

  def handle_info(:tick, state) do
    state =
      state.cameras
      |> Map.keys()
      |> Enum.reduce(state, &capture_frame(&2, &1))

    {:noreply, schedule_tick(state)}
  end

  defp build_camera(spec) do
    name = Map.fetch!(spec, :name)

    %{
      robot: Map.fetch!(spec, :robot),
      name: name,
      path: Map.get(spec, :path, [:sensor, name]),
      attached_to: Map.get(spec, :attached_to, :robot),
      status: Map.get(spec, :status, :running),
      ended?: false,
      stream: Map.get(spec, :stream, default_stream()),
      sequence: 0,
      latest: nil
    }
  end

  defp capture_frame(state, name) do
    camera = Map.fetch!(state.cameras, name)
    sequence = camera.sequence + 1

    frame = %{
      data: Frames.at(sequence - 1),
      format: stream_format(camera.stream),
      sequence: sequence,
      width: stream_field(camera.stream, :width),
      height: stream_field(camera.stream, :height)
    }

    state
    |> put_in([:cameras, name], %{camera | sequence: sequence, latest: frame})
    |> deliver_to_waiting(name)
  end

  defp count_consumers(state, name) do
    Enum.count(state.sessions, fn {_id, session} -> session.camera == name end)
  end

  defp default_stream, do: %{format: :jpeg, width: 160, height: 120, frame_rate: 10.0}

  defp deliver(state, id, session) do
    camera = Map.fetch!(state.cameras, session.camera)
    frame = camera.latest
    send(session.owner, {:synthetic_camera_frame, session.ref, {:ok, frame}})
    put_in(state.sessions[id], %{session | demand?: false, last_sequence: frame.sequence})
  end

  defp deliver_to_waiting(state, name) do
    state.sessions
    |> Enum.filter(fn {_id, session} -> session.camera == name and waiting?(state, session) end)
    |> Enum.reduce(state, fn {id, session}, state -> deliver(state, id, session) end)
  end

  defp camera_of(state, id) do
    case Map.fetch(state.sessions, id) do
      {:ok, session} -> session.camera
      :error -> nil
    end
  end

  defp demand(state, id) do
    case Map.fetch(state.sessions, id) do
      {:ok, session} ->
        cond do
          waiting?(state, %{session | demand?: true}) ->
            deliver(state, id, session)

          ended?(state, session) ->
            send(session.owner, {:synthetic_camera_frame, session.ref, {:error, :end_of_capture}})
            state

          true ->
            put_in(state.sessions[id], %{session | demand?: true})
        end

      :error ->
        state
    end
  end

  defp ended?(state, session) do
    state.cameras |> Map.fetch!(session.camera) |> Map.get(:ended?, false)
  end

  defp flush(ref) do
    receive do
      {:synthetic_camera_frame, ^ref, _result} -> flush(ref)
    after
      0 -> :ok
    end
  end

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

  defp notify(state, event) do
    Enum.each(state.watchers, &send(&1, {:synthetic_camera, event}))
    state
  end

  defp open_session(state, camera, opts, owner, server) do
    requested = Keyword.get(opts, :format)
    actual = stream_format(camera.stream)

    if requested && actual && requested != actual do
      {:reply, {:error, :unsupported_format}, state}
    else
      id = state.next_id
      ref = make_ref()
      Process.monitor(owner)

      session = %{
        camera: camera.name,
        owner: owner,
        ref: ref,
        demand?: false,
        last_sequence: 0
      }

      state =
        state
        |> put_in([:sessions, id], session)
        |> Map.put(:next_id, id + 1)
        |> started(camera.name)

      reply = %__MODULE__{
        camera: camera.name,
        id: id,
        owner: owner,
        ref: ref,
        robot: camera.robot,
        server: server
      }

      {:reply, {:ok, reply}, state}
    end
  end

  defp release(state, id, reason) do
    case Map.pop(state.sessions, id) do
      {nil, _sessions} ->
        state

      {session, sessions} ->
        %{state | sessions: sessions}
        |> notify({:consumer_released, session.camera, reason})
        |> stopped(session.camera)
    end
  end

  defp schedule_tick(%{clock: {:rate, hertz}} = state) do
    Process.send_after(self(), :tick, trunc(1000 / hertz))
    state
  end

  defp schedule_tick(state), do: state

  defp started(state, name) do
    if count_consumers(state, name) == 1 do
      state
      |> put_in([:cameras, name, :status], :capturing)
      |> notify({:capture_started, name})
    else
      state
    end
  end

  defp stopped(state, name) do
    if count_consumers(state, name) == 0 do
      state
      |> put_in([:cameras, name, :status], :running)
      |> notify({:capture_stopped, name})
    else
      state
    end
  end

  defp stream_field(nil, _key), do: nil
  defp stream_field(stream, key), do: Map.get(stream, key)

  defp stream_format(nil), do: nil
  defp stream_format(stream), do: Map.get(stream, :format)

  defp update_session(state, id, fun) do
    case Map.fetch(state.sessions, id) do
      {:ok, session} -> put_in(state.sessions[id], fun.(session))
      :error -> state
    end
  end

  defp waiting?(state, session) do
    camera = Map.fetch!(state.cameras, session.camera)
    session.demand? and camera.latest != nil and camera.latest.sequence > session.last_sequence
  end
end
