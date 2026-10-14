# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.EventStreamThrottleTest do
  @moduledoc """
  Tests for `EventStream`'s debounce + flush behaviour.

  Uses a tiny host LiveView (`BB.LiveView.EventStreamHostLive`) so the
  component can be mounted in isolation. The flush interval and debounce
  window default to far beyond the length of a test, and the test flushes by
  sending the host `:flush`, so no outcome depends on a timer.
  """

  use BB.LiveView.ConnCase

  import Phoenix.LiveViewTest

  alias BB.LiveView.Components.EventStream
  alias BB.LiveView.EventStreamHostLive
  alias BB.Message
  alias BB.Message.Sensor.BatteryState
  alias BB.Message.Sensor.JointState

  @longer_than_any_test :timer.hours(1)
  @debounce_window_ms 100

  defp mount_host(conn, opts \\ %{}) do
    session =
      Map.merge(
        %{
          "flush_interval_ms" => @longer_than_any_test,
          "debounce_window_ms" => @longer_than_any_test
        },
        opts
      )

    live_isolated(conn, EventStreamHostLive, session: session)
  end

  defp joint_state_message do
    %Message{
      wall_time: System.os_time(:nanosecond),
      payload: %JointState{names: [:joint1], positions: [0.0], velocities: [], efforts: []}
    }
  end

  defp battery_state_message do
    %Message{
      wall_time: System.os_time(:nanosecond),
      payload: %BatteryState{voltage: 12.0}
    }
  end

  defp inject(view, path, message), do: send(view.pid, {:inject, path, message})

  defp flush_now(view), do: send(view.pid, :flush)

  # The host hands each message to the component with a `send_update` to
  # itself, which queues behind the render's own sync with the view. A second
  # render is the first to see the component updated.
  defp render_after_update(view) do
    render(view)
    render(view)
  end

  defp assert_flush_fired(view) do
    view_pid = view.pid

    assert_receive {:trace, ^view_pid, :receive,
                    {:phoenix, :send_update, {{EventStream, "event_stream"}, %{event: :flush}}}},
                   1_000
  end

  describe "flush" do
    test "buffers a new message until the flush interval elapses", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      inject(view, [:sensor, :imu], joint_state_message())

      assert render_after_update(view) =~ "0 messages"

      flush_now(view)

      assert render_after_update(view) =~ "1 messages"
    end

    test "batches multiple distinct messages into one render", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      inject(view, [:sensor, :imu], joint_state_message())
      inject(view, [:sensor, :battery], battery_state_message())

      assert render_after_update(view) =~ "0 messages"

      flush_now(view)

      assert render_after_update(view) =~ "2 messages"
    end

    test "schedules a fresh flush for messages arriving after the previous one fired",
         %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{"flush_interval_ms" => 20})
      :erlang.trace(view.pid, true, [:receive])

      inject(view, [:sensor, :imu], joint_state_message())
      assert_flush_fired(view)
      assert render(view) =~ "1 messages"

      inject(view, [:sensor, :battery], battery_state_message())
      assert_flush_fired(view)
      assert render(view) =~ "2 messages"
    end
  end

  describe "debounce" do
    test "drops repeats of the same path + payload type within the window", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      for _ <- 1..5 do
        inject(view, [:sensor, :imu], joint_state_message())
      end

      flush_now(view)

      assert render_after_update(view) =~ "1 messages"
    end

    test "lets different payload types from the same path through", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      inject(view, [:sensor, :imu], joint_state_message())
      inject(view, [:sensor, :imu], battery_state_message())
      flush_now(view)

      assert render_after_update(view) =~ "2 messages"
    end

    test "lets the same payload type from different paths through", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      inject(view, [:sensor, :imu], joint_state_message())
      inject(view, [:sensor, :arm], joint_state_message())
      flush_now(view)

      assert render_after_update(view) =~ "2 messages"
    end

    test "accepts another message once the debounce window has elapsed", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{"debounce_window_ms" => @debounce_window_ms})

      inject(view, [:sensor, :imu], joint_state_message())
      flush_now(view)
      assert render_after_update(view) =~ "1 messages"

      Process.sleep(@debounce_window_ms)

      inject(view, [:sensor, :imu], joint_state_message())
      flush_now(view)
      assert render_after_update(view) =~ "2 messages"
    end
  end

  describe "interaction with paused" do
    test "skips both buffering and debounce tracking when paused", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn)

      view
      |> element("button", "Pause")
      |> render_click()

      inject(view, [:sensor, :imu], joint_state_message())
      flush_now(view)

      assert render_after_update(view) =~ "0 messages"

      view
      |> element("button", "Resume")
      |> render_click()

      inject(view, [:sensor, :imu], joint_state_message())
      flush_now(view)

      assert render_after_update(view) =~ "1 messages"
    end
  end
end
