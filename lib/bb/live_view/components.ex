# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components do
  @moduledoc """
  Shared UI components for the BB Dashboard.

  Provides reusable function components for building the dashboard interface.
  """

  use Phoenix.Component

  @doc """
  Renders a widget card with header and body.

  ## Examples

      <.widget title="Safety">
        <p>Widget content here</p>
      </.widget>

      <.widget title="Joints" loading={true}>
        <p>Loading...</p>
      </.widget>
  """
  attr(:title, :string, required: true)
  attr(:loading, :boolean, default: false)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)
  slot(:actions)

  def widget(assigns) do
    ~H"""
    <div class={["bb-widget", @class]}>
      <div class="bb-widget-header">
        <span class="bb-widget-title">{@title}</span>
        <div :if={@actions != []} class="bb-widget-actions">
          {render_slot(@actions)}
        </div>
      </div>
      <div class="bb-widget-body">
        <div :if={@loading} class="bb-widget-loading">
          <.spinner />
        </div>
        <div :if={!@loading}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading spinner.
  """
  def spinner(assigns) do
    ~H"""
    <div class="bb-spinner" role="status" aria-label="Loading">
      <svg class="bb-spinner-icon" viewBox="0 0 24 24" fill="none">
        <circle
          class="bb-spinner-track"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          stroke-width="3"
        />
        <path
          class="bb-spinner-head"
          d="M12 2a10 10 0 0 1 10 10"
          stroke="currentColor"
          stroke-width="3"
          stroke-linecap="round"
        />
      </svg>
    </div>
    """
  end

  @doc """
  Renders a status badge.

  ## Examples

      <.badge variant="success">Armed</.badge>
      <.badge variant="danger">Error</.badge>
  """
  attr(:variant, :string, default: "muted", values: ~w(success warning danger muted))
  slot(:inner_block, required: true)

  def badge(assigns) do
    ~H"""
    <span class={"bb-badge bb-badge-#{@variant}"}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Click me</.button>
      <.button variant="primary" disabled={true}>Submit</.button>
  """
  attr(:type, :string, default: "button")
  attr(:variant, :string, default: "outline", values: ~w(primary danger outline))
  attr(:disabled, :boolean, default: false)
  attr(:class, :string, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={["bb-button", "bb-button-#{@variant}", @class]}
      disabled={@disabled}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an empty state message.

  ## Examples

      <.empty_state message="No events yet" />
  """
  attr(:message, :string, required: true)
  attr(:icon, :string, default: nil)

  def empty_state(assigns) do
    ~H"""
    <div class="bb-empty-state">
      <p class="bb-empty-state-message">{@message}</p>
    </div>
    """
  end

  @doc """
  Renders an error message.

  ## Examples

      <.error_message message="Failed to load robot data" />
  """
  attr(:message, :string, required: true)

  def error_message(assigns) do
    ~H"""
    <div class="bb-error-message" role="alert">
      <span class="bb-error-icon">!</span>
      <span>{@message}</span>
    </div>
    """
  end
end
