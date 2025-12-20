# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.EventStream do
  @moduledoc """
  LiveComponent for displaying a live stream of BB messages.

  Shows real-time messages from the robot's PubSub with:
  - Timestamps and path information
  - Message type and summary
  - Pause/Resume functionality
  - Clear messages
  - Click to expand message details
  """
  use Phoenix.LiveComponent

  @max_messages 100

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       messages: [],
       paused: false,
       expanded: MapSet.new()
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:new_message, path, message}}, socket) do
    if socket.assigns.paused do
      {:ok, socket}
    else
      msg_data = format_message(path, message)

      messages =
        [msg_data | socket.assigns.messages]
        |> Enum.take(@max_messages)

      {:ok, assign(socket, :messages, messages)}
    end
  end

  def update(%{robot_module: _robot_module} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-event-stream">
      <div class="bb-event-toolbar">
        <div class="bb-event-controls">
          <button
            type="button"
            class={"bb-button #{if @paused, do: "bb-button-success", else: "bb-button-warning"}"}
            phx-click="toggle_pause"
            phx-target={@myself}
          >
            {if @paused, do: "Resume", else: "Pause"}
          </button>
          <button
            type="button"
            class="bb-button bb-button-outline"
            phx-click="clear"
            phx-target={@myself}
          >
            Clear
          </button>
          <span class="bb-event-count">{length(@messages)} messages</span>
        </div>
      </div>

      <div class="bb-event-list">
        <div :if={@messages == []} class="bb-empty-state">
          <p class="bb-empty-state-message">
            {if @paused, do: "Paused - no new messages", else: "Waiting for messages..."}
          </p>
        </div>

        <div
          :for={msg <- @messages}
          class="bb-event-message"
          phx-click="toggle_expand"
          phx-target={@myself}
          phx-value-id={msg.id}
        >
          <div class="bb-event-header">
            <span class="bb-event-timestamp">{msg.timestamp}</span>
            <span class="bb-event-path">{msg.path}</span>
            <span class="bb-event-type">{msg.short_type}</span>
            <span :if={msg.summary} class="bb-event-summary">{msg.summary}</span>
          </div>

          <div :if={MapSet.member?(@expanded, msg.id)} class="bb-event-payload">
            <div class="bb-event-full-type">{msg.type}</div>
            <div class="bb-event-fields">
              <div :for={field <- msg.fields} class="bb-event-field">
                <span class="bb-event-field-name">{field.name}:</span>
                <span class="bb-event-field-value">{field.value}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, not socket.assigns.paused)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, messages: [], expanded: MapSet.new())}
  end

  def handle_event("toggle_expand", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end

    {:noreply, assign(socket, :expanded, expanded)}
  end

  defp format_message(path, message) do
    now = DateTime.utc_now()

    timestamp_str =
      now
      |> Calendar.strftime("%H:%M:%S.%f")
      |> String.slice(0, 12)

    payload_struct = message.payload
    type_name = payload_struct.__struct__ |> Module.split() |> Enum.join(".")

    %{
      id: System.unique_integer([:positive]),
      timestamp: timestamp_str,
      path: format_path(path),
      type: type_name,
      short_type: short_type_name(payload_struct.__struct__),
      summary: format_payload_summary(payload_struct),
      fields: format_payload_fields(payload_struct)
    }
  end

  defp format_path(path) do
    Enum.map_join(path, ".", &format_path_element/1)
  end

  defp format_path_element(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp format_path_element(ref) when is_reference(ref), do: inspect(ref)
  defp format_path_element(other), do: inspect(other)

  defp short_type_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp format_payload_summary(payload) do
    case payload do
      %BB.Message.Sensor.JointState{names: names} ->
        "#{length(names)} joint(s)"

      %BB.Message.Actuator.Command.Position{position: pos} ->
        format_value(pos)

      %BB.StateMachine.Transition{from: from, to: to} ->
        "#{from} → #{to}"

      _ ->
        nil
    end
  end

  defp format_payload_fields(payload) do
    payload
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {key, value} ->
      %{
        name: Atom.to_string(key),
        value: format_value(value)
      }
    end)
  end

  defp format_value([]), do: "[]"

  defp format_value(value) when is_list(value) do
    cond do
      Enum.all?(value, &is_number/1) ->
        values = Enum.map_join(value, ", ", &format_number/1)
        "[#{values}]"

      Enum.all?(value, &is_atom/1) ->
        values = Enum.map_join(value, ", ", &Atom.to_string/1)
        "[#{values}]"

      true ->
        inspect(value, limit: 10)
    end
  end

  defp format_value(value) when is_float(value), do: format_number(value)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value, limit: 10)

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp format_number(n), do: Integer.to_string(n)
end
