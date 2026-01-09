# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Command do
  @moduledoc """
  LiveComponent for executing robot commands.

  Displays available commands in tabs with:
  - Dynamic form for each command's arguments
  - Execute button with loading state
  - Result/error display
  - State-aware command availability
  """
  use Phoenix.LiveComponent

  alias BB.Dsl.Info, as: DslInfo
  alias BB.Robot.Runtime, as: RobotRuntime

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       commands: [],
       active_tab: nil,
       state: :disarmed,
       executing: nil,
       result: nil,
       error: nil,
       form_values: %{}
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:state_changed, new_state}}, socket) do
    {:ok, assign(socket, :state, new_state)}
  end

  def update(%{event: {:command_result, result}}, socket) do
    {:ok,
     socket
     |> assign(:executing, nil)
     |> assign(:result, result)
     |> assign(:error, nil)}
  end

  def update(%{event: {:command_error, error}}, socket) do
    {:ok,
     socket
     |> assign(:executing, nil)
     |> assign(:result, nil)
     |> assign(:error, error)}
  end

  def update(%{robot_module: robot_module} = assigns, socket) do
    socket =
      if socket.assigns[:robot_module] != robot_module do
        initialize_for_robot(socket, robot_module)
      else
        socket
      end

    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp initialize_for_robot(socket, robot_module) do
    case load_robot_state(robot_module) do
      {:ok, commands, state} ->
        active_tab = if commands != [], do: hd(commands).name, else: nil

        socket
        |> assign(:robot_module, robot_module)
        |> assign(:commands, commands)
        |> assign(:state, state)
        |> assign(:active_tab, active_tab)

      :error ->
        assign(socket, :robot_module, robot_module)
    end
  end

  defp load_robot_state(robot_module) do
    if valid_robot?(robot_module) do
      try do
        commands = discover_commands(robot_module)
        state = RobotRuntime.state(robot_module)
        {:ok, commands, state}
      rescue
        ArgumentError -> :error
      end
    else
      :error
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="bb-command">
      <div :if={@commands == []} class="bb-empty-state">
        <p class="bb-empty-state-message">No commands available</p>
      </div>

      <div :if={@commands != []}>
        <div class="bb-command-tabs">
          <button
            :for={cmd <- @commands}
            type="button"
            class={"bb-command-tab #{if cmd.name == @active_tab, do: "active", else: ""}"}
            phx-click="select_tab"
            phx-target={@myself}
            phx-value-tab={cmd.name}
          >
            {cmd.name}
          </button>
        </div>

        <div :if={@active_tab} class="bb-command-content">
          <% cmd = Enum.find(@commands, fn c -> c.name == @active_tab end) %>
          <% can_execute = @state in cmd.allowed_states %>

          <div class="bb-command-header">
            <span class="bb-command-name">{cmd.name}</span>
            <span class={"bb-state-badge #{if can_execute, do: "allowed", else: "blocked"}"}>
              {if can_execute, do: "Ready", else: "Requires: #{Enum.join(cmd.allowed_states, ", ")}"}
            </span>
          </div>

          <form phx-submit="execute" phx-target={@myself}>
            <input type="hidden" name="command" value={cmd.name} />

            <div :if={cmd.arguments == []} class="bb-no-args">
              No arguments required
            </div>

            <div :for={arg <- cmd.arguments} class="bb-form-field">
              <label>
                {arg.name}
                <span :if={arg.required} class="bb-required">*</span>
              </label>

              <%= render_input(arg, @form_values) %>

              <span :if={arg.doc} class="bb-field-doc">{arg.doc}</span>
            </div>

            <button
              type="submit"
              class="bb-button bb-button-primary"
              disabled={not can_execute or @executing != nil}
            >
              {if @executing == cmd.name, do: "Executing...", else: "Execute"}
            </button>
          </form>

          <div :if={@result} class="bb-command-result success">
            <pre>{@result}</pre>
          </div>

          <div :if={@error} class="bb-command-result error">
            <pre>{@error}</pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_input(arg, form_values) do
    value = Map.get(form_values, arg.name, arg.default)

    case arg.type do
      "boolean" ->
        assigns = %{arg: arg, checked: value == true or value == "true"}

        ~H"""
        <input type="checkbox" name={"args[#{@arg.name}]"} value="true" checked={@checked} />
        """

      "enum:" <> values_str ->
        values = parse_enum_values(values_str)
        assigns = %{arg: arg, values: values, value: value}

        ~H"""
        <select name={"args[#{@arg.name}]"}>
          <option :for={v <- @values} value={v} selected={v == @value}>{v}</option>
        </select>
        """

      type when type in ["integer", "float"] ->
        step = if type == "float", do: "0.01", else: "1"
        assigns = %{arg: arg, value: value, step: step}

        ~H"""
        <input type="number" name={"args[#{@arg.name}]"} value={@value} step={@step} class="bb-input" />
        """

      _ ->
        assigns = %{arg: arg, value: value}

        ~H"""
        <input type="text" name={"args[#{@arg.name}]"} value={@value} class="bb-input" />
        """
    end
  end

  defp parse_enum_values(values_str) do
    values_str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(", ")
    |> Enum.map(&String.trim/1)
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, assign(socket, active_tab: tab_atom, result: nil, error: nil)}
  end

  def handle_event("execute", %{"command" => cmd_name, "args" => args}, socket) do
    execute_command(socket, cmd_name, args)
  end

  def handle_event("execute", %{"command" => cmd_name}, socket) do
    execute_command(socket, cmd_name, %{})
  end

  defp execute_command(socket, cmd_name, args) do
    cmd_atom = String.to_existing_atom(cmd_name)

    if valid_robot?(socket.assigns.robot_module) do
      parsed_args = parse_args(args)
      spawn_command_task(socket, cmd_atom, parsed_args)

      {:noreply,
       socket
       |> assign(:executing, cmd_atom)
       |> assign(:result, nil)
       |> assign(:error, nil)}
    else
      {:noreply, assign(socket, :error, "No valid robot connected")}
    end
  end

  defp parse_args(args) do
    args
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), parse_value(v)} end)
    |> Map.new()
  end

  defp spawn_command_task(socket, cmd_atom, parsed_args) do
    liveview_pid = socket.root_pid
    component_id = socket.assigns.id
    robot_module = socket.assigns.robot_module

    Task.start(fn ->
      case RobotRuntime.execute(robot_module, cmd_atom, parsed_args) do
        {:ok, pid} ->
          result = BB.Command.await(pid, 30_000)
          notify_command_complete(liveview_pid, component_id, result)

        {:error, _} = error ->
          notify_command_complete(liveview_pid, component_id, error)
      end
    end)
  end

  defp notify_command_complete(liveview_pid, component_id, {:ok, result}) do
    send(liveview_pid, {:command_complete, component_id, {:ok, inspect(result)}})
  end

  defp notify_command_complete(liveview_pid, component_id, {:ok, result, _metadata}) do
    send(liveview_pid, {:command_complete, component_id, {:ok, inspect(result)}})
  end

  defp notify_command_complete(liveview_pid, component_id, {:error, reason}) do
    send(liveview_pid, {:command_complete, component_id, {:error, inspect(reason)}})
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(":" <> rest = value) when byte_size(rest) > 0 do
    String.to_existing_atom(rest)
  rescue
    ArgumentError -> value
  end

  defp parse_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> value
        end
    end
  end

  defp parse_value(value), do: value

  defp discover_commands(robot_module) do
    robot_module
    |> DslInfo.commands()
    |> Enum.map(&format_command/1)
    |> Enum.sort_by(& &1.name)
  end

  defp format_command(cmd) do
    %{
      name: cmd.name,
      handler: cmd.handler,
      timeout: cmd.timeout,
      allowed_states: cmd.allowed_states,
      arguments: Enum.map(cmd.arguments, &format_argument/1)
    }
  end

  defp format_argument(arg) do
    %{
      name: arg.name,
      type: format_type(arg.type),
      required: arg.required,
      default: arg.default,
      doc: arg.doc
    }
  end

  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:in, values}), do: "enum:#{inspect(values)}"
  defp format_type(type), do: inspect(type)

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
