# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Dev.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Dev.PubSub},
      %{
        id: BB.Supervisor,
        start: {BB.Supervisor, :start_link, [Dev.TestRobot]}
      },
      DevWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Dev.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DevWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
