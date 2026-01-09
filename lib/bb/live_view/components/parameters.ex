# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.Parameters do
  @moduledoc """
  LiveComponent for viewing and editing robot parameters.

  Displays parameters in a tab-based interface with:
  - Local parameter groups as tabs
  - Remote bridge parameters in separate tabs
  - Appropriate input controls based on parameter type
  - Real-time updates via PubSub
  """
  use Phoenix.LiveComponent

  alias BB.Dsl.Info, as: DslInfo
  alias BB.Parameter
  alias BB.Robot.Runtime, as: RobotRuntime

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       tabs: [],
       parameters: %{},
       active_tab: nil
     )}
  end

  @impl Phoenix.LiveComponent
  def update(%{event: {:parameter_changed, path, new_value}}, socket) do
    tab_id = get_tab_id_for_path(path)

    updated_params =
      update_in(socket.assigns.parameters, [tab_id, path], fn param ->
        if param, do: %{param | value: new_value}, else: param
      end)

    {:ok, assign(socket, :parameters, updated_params)}
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
    case load_parameters(robot_module) do
      {:ok, tabs, parameters, active_tab} ->
        socket
        |> assign(:robot_module, robot_module)
        |> assign(:tabs, tabs)
        |> assign(:parameters, parameters)
        |> assign(:active_tab, active_tab)

      :error ->
        assign(socket, :robot_module, robot_module)
    end
  end

  defp load_parameters(robot_module) do
    if valid_robot?(robot_module) do
      try do
        {tabs, parameters} = discover_local_parameters(robot_module)
        {bridge_tabs, bridge_params} = discover_bridge_parameters(robot_module)

        all_tabs = tabs ++ bridge_tabs
        all_params = Map.merge(parameters, bridge_params)

        active_tab =
          case all_tabs do
            [first | _] -> first.id
            [] -> nil
          end

        {:ok, all_tabs, all_params, active_tab}
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
    <div class="bb-parameters">
      <div :if={@tabs == []} class="bb-empty-state">
        <p class="bb-empty-state-message">No parameters defined</p>
      </div>

      <div :if={@tabs != []}>
        <div class="bb-param-tabs">
          <button
            :for={tab <- @tabs}
            type="button"
            class={"bb-param-tab #{if tab.id == @active_tab, do: "active", else: ""} #{tab.type}"}
            phx-click="select_tab"
            phx-target={@myself}
            phx-value-tab={format_tab_id(tab.id)}
          >
            {tab.label}
            <span :if={tab.type == :remote} class="bb-remote-badge">remote</span>
          </button>
        </div>

        <div :if={@active_tab} class="bb-param-content">
          <% tab = Enum.find(@tabs, fn t -> t.id == @active_tab end) %>
          <% tab_params = Map.get(@parameters, @active_tab, %{}) %>

          <div :if={is_map(tab_params) and Map.has_key?(tab_params, :__error__)} class="bb-param-error">
            <p class="bb-error-text">{tab_params.__error__}</p>
            <button
              :if={tab.type == :remote}
              type="button"
              class="bb-button bb-button-outline"
              phx-click="refresh_remote"
              phx-target={@myself}
              phx-value-bridge={tab.bridge_name}
            >
              Refresh
            </button>
          </div>

          <div
            :if={is_map(tab_params) and not Map.has_key?(tab_params, :__error__)}
            class="bb-param-list"
          >
            <div :if={tab_params == %{}} class="bb-empty-state">
              <p class="bb-empty-state-message">No parameters in this group</p>
            </div>

            <div :for={{_key, param} <- Enum.sort_by(tab_params, fn {_k, p} -> p.display_name end)} class="bb-param-row">
              <div class="bb-param-info">
                <span class="bb-param-name">{param.display_name}</span>
                <span :if={param.doc} class="bb-param-doc">{param.doc}</span>
              </div>
              <div class="bb-param-input">
                {render_param_input(assigns, param, tab)}
              </div>
            </div>

            <button
              :if={tab.type == :remote}
              type="button"
              class="bb-button bb-button-outline bb-refresh-btn"
              phx-click="refresh_remote"
              phx-target={@myself}
              phx-value-bridge={tab.bridge_name}
            >
              Refresh
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_param_input(assigns, param, tab) do
    has_limits = param.min != nil and param.max != nil
    is_remote = tab.type == :remote
    path_str = format_path_string(param[:path] || param[:id])

    assigns =
      assigns
      |> Map.put(:param, param)
      |> Map.put(:tab, tab)
      |> Map.put(:has_limits, has_limits)
      |> Map.put(:is_remote, is_remote)
      |> Map.put(:path_str, path_str)

    input_type = determine_input_type(param.type, has_limits)
    render_input_by_type(input_type, assigns)
  end

  defp determine_input_type("boolean", _has_limits), do: :boolean
  defp determine_input_type("atom", _has_limits), do: :atom
  defp determine_input_type("float", true), do: :slider
  defp determine_input_type("float", false), do: :number
  defp determine_input_type("integer", true), do: :slider
  defp determine_input_type("integer", false), do: :number
  defp determine_input_type("unit:" <> _, true), do: :slider
  defp determine_input_type("unit:" <> _, false), do: :number
  defp determine_input_type(_, _has_limits), do: :text

  defp render_input_by_type(:boolean, assigns), do: render_boolean_input(assigns)
  defp render_input_by_type(:slider, assigns), do: render_slider_input(assigns)
  defp render_input_by_type(:number, assigns), do: render_number_input(assigns)
  defp render_input_by_type(:atom, assigns), do: render_atom_input(assigns)
  defp render_input_by_type(:text, assigns), do: render_text_input(assigns)

  defp render_boolean_input(assigns) do
    ~H"""
    <label class="bb-toggle">
      <input
        type="checkbox"
        checked={@param.value == true}
        phx-click="toggle_boolean"
        phx-target={@myself}
        phx-value-path={@path_str}
        phx-value-remote={@is_remote}
        phx-value-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
      />
      <span class="bb-toggle-slider"></span>
    </label>
    """
  end

  defp render_slider_input(assigns) do
    step =
      if assigns.param.type == "integer",
        do: "1",
        else: to_string((assigns.param.max - assigns.param.min) / 100)

    unit = extract_unit(assigns.param.type)

    assigns =
      assigns
      |> Map.put(:step, step)
      |> Map.put(:unit, unit)

    ~H"""
    <div class="bb-slider-input" phx-hook="DebouncedSlider" id={"slider-#{@path_str}"}>
      <input
        type="range"
        min={@param.min}
        max={@param.max}
        step={@step}
        value={@param.value || 0}
        data-path={@path_str}
        data-remote={@is_remote}
        data-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
        phx-target={@myself}
      />
      <input
        type="number"
        min={@param.min}
        max={@param.max}
        step={@step}
        value={@param.value || 0}
        phx-change="set_parameter"
        phx-target={@myself}
        name="value"
        phx-value-path={@path_str}
        phx-value-remote={@is_remote}
        phx-value-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
        class="bb-input"
      />
      <span :if={@unit} class="bb-unit-label">{@unit}</span>
    </div>
    """
  end

  defp render_number_input(assigns) do
    step = if assigns.param.type == "integer", do: "1", else: "0.01"
    unit = extract_unit(assigns.param.type)

    assigns =
      assigns
      |> Map.put(:step, step)
      |> Map.put(:unit, unit)

    ~H"""
    <div class="bb-number-input">
      <input
        type="number"
        step={@step}
        value={@param.value || 0}
        phx-change="set_parameter"
        phx-target={@myself}
        name="value"
        phx-value-path={@path_str}
        phx-value-remote={@is_remote}
        phx-value-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
        class="bb-input"
      />
      <span :if={@unit} class="bb-unit-label">{@unit}</span>
    </div>
    """
  end

  defp render_atom_input(assigns) do
    display_value = if assigns.param.value, do: ":#{assigns.param.value}", else: ""
    assigns = Map.put(assigns, :display_value, display_value)

    ~H"""
    <input
      type="text"
      value={@display_value}
      phx-change="set_parameter"
      phx-target={@myself}
      name="value"
      phx-value-path={@path_str}
      phx-value-remote={@is_remote}
      phx-value-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
      class="bb-input bb-atom-input"
    />
    """
  end

  defp render_text_input(assigns) do
    ~H"""
    <input
      type="text"
      value={@param.value || ""}
      phx-change="set_parameter"
      phx-target={@myself}
      name="value"
      phx-value-path={@path_str}
      phx-value-remote={@is_remote}
      phx-value-bridge={if @is_remote, do: @tab.bridge_name, else: ""}
      class="bb-input"
    />
    """
  end

  defp extract_unit("unit:" <> unit), do: unit
  defp extract_unit(_), do: nil

  @impl Phoenix.LiveComponent
  def handle_event("select_tab", %{"tab" => tab_str}, socket) do
    tab_id = parse_tab_id(tab_str)
    {:noreply, assign(socket, :active_tab, tab_id)}
  end

  def handle_event("toggle_boolean", params, socket) do
    path_str = params["path"]
    is_remote = params["remote"] == "true"
    current_value = get_current_value(socket, path_str)
    new_value = not (current_value == true)

    apply_parameter_change(socket, path_str, new_value, is_remote, params["bridge"])
  end

  def handle_event("set_parameter", params, socket) do
    path_str = params["path"]
    value = params["value"]
    is_remote = params["remote"] == "true"
    bridge = params["bridge"]
    param_type = get_param_type(socket, path_str)

    parsed_value = parse_value(value, param_type)
    apply_parameter_change(socket, path_str, parsed_value, is_remote, bridge)
  end

  def handle_event("slider_change", params, socket) do
    path_str = params["path"]
    value = params["value"]
    is_remote = params["remote"] == "true"
    bridge = params["bridge"]
    param_type = get_param_type(socket, path_str)

    parsed_value = parse_value(value, param_type)
    apply_parameter_change(socket, path_str, parsed_value, is_remote, bridge)
  end

  def handle_event("refresh_remote", %{"bridge" => bridge_str}, socket) do
    bridge_atom = String.to_existing_atom(bridge_str)
    params = fetch_remote_params(socket.assigns.robot_module, bridge_atom)
    tab_id = {:bridge, bridge_atom}

    updated_params = Map.put(socket.assigns.parameters, tab_id, params)
    {:noreply, assign(socket, :parameters, updated_params)}
  end

  defp apply_parameter_change(socket, path_str, value, is_remote, bridge) do
    result =
      if is_remote do
        bridge_atom = String.to_existing_atom(bridge)
        Parameter.set_remote(socket.assigns.robot_module, bridge_atom, path_str, value)
      else
        path = String.split(path_str, ".") |> Enum.map(&String.to_existing_atom/1)
        Parameter.set(socket.assigns.robot_module, path, value)
      end

    case result do
      :ok ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp get_current_value(socket, path_str) do
    path = String.split(path_str, ".") |> Enum.map(&String.to_existing_atom/1)
    tab_id = get_tab_id_for_path(path)

    socket.assigns.parameters
    |> Map.get(tab_id, %{})
    |> Map.get(path, %{})
    |> Map.get(:value)
  end

  defp get_param_type(socket, path_str) do
    path = String.split(path_str, ".") |> Enum.map(&String.to_existing_atom/1)
    tab_id = get_tab_id_for_path(path)

    socket.assigns.parameters
    |> Map.get(tab_id, %{})
    |> Map.get(path, %{})
    |> Map.get(:type, "string")
  end

  defp get_tab_id_for_path(path) do
    case path do
      [single] when is_atom(single) -> :general
      [group | _] -> group
    end
  end

  # Parameter discovery

  defp discover_local_parameters(robot_module) do
    params = Parameter.list(robot_module)
    organise_into_tabs(params)
  end

  defp organise_into_tabs(params) do
    grouped =
      params
      |> Enum.group_by(fn {path, _meta} ->
        case path do
          [single] when is_atom(single) -> :general
          [group | _rest] -> group
        end
      end)

    tabs =
      grouped
      |> Map.keys()
      |> Enum.sort_by(fn
        :general -> {0, ""}
        name -> {1, Atom.to_string(name)}
      end)
      |> Enum.map(fn group ->
        %{
          id: group,
          label: format_tab_label(group),
          type: :local
        }
      end)

    parameters =
      grouped
      |> Enum.map(fn {group, params_list} ->
        formatted =
          params_list
          |> Enum.map(&format_local_param/1)
          |> Enum.sort_by(& &1.display_name)
          |> Map.new(fn p -> {p.path, p} end)

        {group, formatted}
      end)
      |> Map.new()

    {tabs, parameters}
  end

  defp format_tab_label(:general), do: "General"
  defp format_tab_label(name), do: name |> Atom.to_string() |> String.capitalize()

  defp format_local_param({path, meta}) do
    display_name =
      case path do
        [_single] -> Atom.to_string(hd(path))
        [_group | rest] -> Enum.map_join(rest, ".", &Atom.to_string/1)
      end

    %{
      path: path,
      display_name: display_name,
      value: meta[:value],
      type: format_type(meta[:type]),
      min: meta[:min],
      max: meta[:max],
      doc: meta[:doc]
    }
  end

  defp format_type(nil), do: "string"
  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:unit, unit}), do: "unit:#{unit}"
  defp format_type(other), do: inspect(other)

  defp discover_bridge_parameters(robot_module) do
    simulation_mode = RobotRuntime.simulation_mode(robot_module)

    bridges =
      robot_module
      |> DslInfo.parameters()
      |> Enum.filter(&is_struct(&1, BB.Dsl.Bridge))
      |> Enum.reject(fn bridge ->
        simulation_mode != nil and bridge.simulation == :omit
      end)

    tabs =
      Enum.map(bridges, fn bridge ->
        %{
          id: {:bridge, bridge.name},
          label: bridge.name |> Atom.to_string() |> String.capitalize(),
          type: :remote,
          bridge_name: bridge.name
        }
      end)

    parameters =
      bridges
      |> Enum.map(fn bridge ->
        params = fetch_remote_params(robot_module, bridge.name)
        {{:bridge, bridge.name}, params}
      end)
      |> Map.new()

    {tabs, parameters}
  end

  defp fetch_remote_params(robot_module, bridge_name) do
    case Parameter.list_remote(robot_module, bridge_name) do
      {:ok, params} ->
        params
        |> Enum.map(fn p ->
          id = p[:id] || p["id"]

          %{
            id: id,
            display_name: id,
            value: p[:value] || p["value"],
            type: format_type(p[:type] || p["type"]),
            min: p[:min] || p["min"],
            max: p[:max] || p["max"],
            doc: p[:doc] || p["doc"]
          }
        end)
        |> Map.new(fn p -> {p.id, p} end)

      {:error, _reason} ->
        %{__error__: "Failed to load remote parameters"}
    end
  end

  # Tab ID formatting

  defp format_tab_id(:general), do: "general"
  defp format_tab_id({:bridge, name}), do: "bridge:#{name}"
  defp format_tab_id(name) when is_atom(name), do: Atom.to_string(name)

  defp parse_tab_id("general"), do: :general
  defp parse_tab_id("bridge:" <> name), do: {:bridge, String.to_existing_atom(name)}
  defp parse_tab_id(name), do: String.to_existing_atom(name)

  defp format_path_string(path) when is_list(path),
    do: Enum.map_join(path, ".", &Atom.to_string/1)

  defp format_path_string(id), do: to_string(id)

  # Value parsing

  defp parse_value(value, "boolean"), do: value == true or value == "true"

  defp parse_value(value, "integer") do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> value
    end
  end

  defp parse_value(value, "float"), do: parse_float_value(value)
  defp parse_value(value, "unit:" <> _unit), do: parse_float_value(value)

  defp parse_value(value, "atom") do
    case to_string(value) do
      ":" <> rest -> String.to_existing_atom(rest)
      rest -> String.to_existing_atom(rest)
    end
  end

  defp parse_value(value, _type), do: value

  defp parse_float_value(value) do
    case Float.parse(to_string(value)) do
      {float, _} -> float
      :error -> value
    end
  end

  defp valid_robot?(robot_module) when is_atom(robot_module) do
    function_exported?(robot_module, :robot, 0) and
      function_exported?(robot_module, :spark_dsl_config, 0)
  end

  defp valid_robot?(_), do: false
end
