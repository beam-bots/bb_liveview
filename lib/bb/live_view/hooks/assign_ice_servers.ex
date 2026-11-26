# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Hooks.AssignIceServers do
  @moduledoc """
  LiveView on_mount hook that assigns the ICE servers camera previews use as
  `:ice_servers`.

  Given either a list, or a `{module, function, args}` called on every mount —
  for TURN credentials that are read at runtime or expire, which a list
  written into the router would bake into the compiled application.

  Applied by the `bb_dashboard/2` router macro.
  """

  import Phoenix.Component

  @doc false
  def on_mount({module, function, args}, _params, _session, socket) do
    {:cont, assign(socket, :ice_servers, apply(module, function, args))}
  end

  def on_mount(ice_servers, _params, _session, socket) when is_list(ice_servers) do
    {:cont, assign(socket, :ice_servers, ice_servers)}
  end
end
