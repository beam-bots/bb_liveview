# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.EventStreamHostLive do
  @moduledoc """
  Minimal LiveView used in tests to host `EventStream` in isolation with
  configurable flush and debounce intervals.

  Messages are injected by sending `{:inject, path, message}` to the LiveView
  process; the LiveView forwards them to the component as a `:new_message`
  event, matching what `DashboardLive` does at runtime.
  """

  use Phoenix.LiveView

  alias BB.LiveView.Components.EventStream

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       flush_interval_ms: Map.get(session, "flush_interval_ms", 500),
       debounce_window_ms: Map.get(session, "debounce_window_ms", 1000)
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:inject, path, message}, socket) do
    send_update(EventStream,
      id: "event_stream",
      event: {:new_message, path, message}
    )

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.live_component
      module={EventStream}
      id="event_stream"
      flush_interval_ms={@flush_interval_ms}
      debounce_window_ms={@debounce_window_ms}
    />
    """
  end
end
