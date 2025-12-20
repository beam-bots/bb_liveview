# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Hooks.AssignRobot do
  @moduledoc """
  LiveView on_mount hook that assigns the robot module to the socket.

  This hook is automatically applied by the `bb_dashboard/2` router macro.
  It validates that the robot module exists and has a `robot/0` function,
  then assigns it to the socket for use by dashboard components.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  @doc """
  Mounts the robot module into the socket assigns.

  The robot module is passed as the second argument from the live_session configuration.
  """
  def on_mount(robot_module, _params, _session, socket) do
    case validate_robot_module(robot_module) do
      :ok ->
        {:cont,
         socket
         |> assign(:robot_module, robot_module)
         |> assign(:page_title, "BB Dashboard")}

      {:error, reason} ->
        {:halt, put_flash(socket, :error, reason)}
    end
  end

  defp validate_robot_module(module) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, "Robot module #{inspect(module)} is not available"}

      not function_exported?(module, :robot, 0) ->
        {:error, "Robot module #{inspect(module)} does not export robot/0"}

      true ->
        :ok
    end
  end

  defp validate_robot_module(_), do: {:error, "Invalid robot module"}
end
