# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Layouts do
  @moduledoc """
  Layout components for the BB Dashboard.

  Provides root and app layouts with bundled CSS and JavaScript.
  """

  use Phoenix.Component

  alias BB.LiveView.Plugs.Static

  @doc """
  Root layout that wraps all dashboard pages.

  Includes the bundled CSS and JavaScript assets.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>{assigns[:page_title] || "BB Dashboard"}</title>
        <link rel="stylesheet" href={Static.asset_path("dashboard.css")} />
        <script type="module" src={Static.asset_path("dashboard.js")}>
        </script>
      </head>
      <body class="bb-dashboard">
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  App layout for dashboard content.

  This is the inner layout that wraps the LiveView content.
  """
  def app(assigns) do
    ~H"""
    <main class="bb-dashboard-main">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    """
  end

  defp flash_group(assigns) do
    ~H"""
    <div class="bb-flash-group">
      <.flash :for={{kind, message} <- @flash} kind={kind} message={message} />
    </div>
    """
  end

  defp flash(assigns) do
    ~H"""
    <div class={"bb-flash bb-flash-#{@kind}"} role="alert">
      {@message}
    </div>
    """
  end
end
