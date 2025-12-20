# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Safety do
  @moduledoc """
  LiveComponent for displaying and controlling robot arming state.

  Shows the current safety state with colour-coded indicators:
  - Green: Armed (ready for operation)
  - Grey: Disarmed (safe state)
  - Yellow: Disarming (transitioning to safe state)
  - Red: Error (disarm failed, may not be safe)

  Provides:
  - Arm/Disarm toggle buttons
  - Force Disarm button (only in error state)
  - Real-time state updates via PubSub
  """
  use Phoenix.LiveComponent

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       state: :disarmed,
       in_error: false,
       error_message: nil,
       show_force_confirm: false
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:state_changed, state, in_error}}, socket) do
    {:ok,
     socket
     |> assign(:state, state)
     |> assign(:in_error, in_error)
     |> assign(:error_message, nil)
     |> assign(:show_force_confirm, false)}
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] != robot_module do
        if valid_robot?(robot_module) do
          safety_state = fetch_safety_state(robot_module)

          socket
          |> assign(:robot_module, robot_module)
          |> assign(:state, safety_state.state)
          |> assign(:in_error, safety_state.in_error)
        else
          assign(socket, :robot_module, robot_module)
        end
      else
        socket
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-safety">
      <div class="bb-safety-status">
        <span class={"bb-safety-indicator bb-safety-#{@state}"}></span>
        <span class="bb-safety-text">{format_state(@state)}</span>
      </div>

      <div class="bb-safety-controls">
        <button
          type="button"
          class="bb-button bb-button-success"
          phx-click="arm"
          phx-target={@myself}
          disabled={@state == :armed or @state == :disarming}
        >
          Arm
        </button>

        <button
          type="button"
          class="bb-button bb-button-outline"
          phx-click="disarm"
          phx-target={@myself}
          disabled={@state == :disarmed or @state == :disarming}
        >
          Disarm
        </button>

        <button
          :if={@in_error and not @show_force_confirm}
          type="button"
          class="bb-button bb-button-danger"
          phx-click="show_force_confirm"
          phx-target={@myself}
        >
          Force Disarm
        </button>

        <div :if={@show_force_confirm} class="bb-safety-confirm">
          <span class="bb-safety-confirm-text">
            Force disarm may leave hardware in an unsafe state. Continue?
          </span>
          <button
            type="button"
            class="bb-button bb-button-danger"
            phx-click="force_disarm"
            phx-target={@myself}
          >
            Yes, Force Disarm
          </button>
          <button
            type="button"
            class="bb-button bb-button-outline"
            phx-click="cancel_force_confirm"
            phx-target={@myself}
          >
            Cancel
          </button>
        </div>
      </div>

      <div :if={@error_message} class="bb-error-message" role="alert">
        <span class="bb-error-icon">!</span>
        <span>{@error_message}</span>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("arm", _params, socket) do
    if valid_robot?(socket.assigns.robot_module) do
      case BB.Safety.arm(socket.assigns.robot_module) do
        :ok ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, :error_message, "Arm failed: #{inspect(reason)}")}
      end
    else
      {:noreply, assign(socket, :error_message, "No valid robot connected")}
    end
  end

  def handle_event("disarm", _params, socket) do
    if valid_robot?(socket.assigns.robot_module) do
      case BB.Safety.disarm(socket.assigns.robot_module) do
        :ok ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, :error_message, "Disarm failed: #{inspect(reason)}")}
      end
    else
      {:noreply, assign(socket, :error_message, "No valid robot connected")}
    end
  end

  def handle_event("show_force_confirm", _params, socket) do
    {:noreply, assign(socket, :show_force_confirm, true)}
  end

  def handle_event("cancel_force_confirm", _params, socket) do
    {:noreply, assign(socket, :show_force_confirm, false)}
  end

  def handle_event("force_disarm", _params, socket) do
    if valid_robot?(socket.assigns.robot_module) do
      case BB.Safety.force_disarm(socket.assigns.robot_module) do
        :ok ->
          {:noreply, assign(socket, :show_force_confirm, false)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:error_message, "Force disarm failed: #{inspect(reason)}")
           |> assign(:show_force_confirm, false)}
      end
    else
      {:noreply,
       socket
       |> assign(:error_message, "No valid robot connected")
       |> assign(:show_force_confirm, false)}
    end
  end

  defp format_state(state) do
    state
    |> Atom.to_string()
    |> String.capitalize()
  end

  defp fetch_safety_state(robot_module) do
    %{
      state: BB.Safety.state(robot_module),
      in_error: BB.Safety.in_error?(robot_module)
    }
  rescue
    ArgumentError -> %{state: :disarmed, in_error: false}
  end

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
