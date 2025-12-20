# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.EventStreamTest do
  use BB.LiveView.FeatureCase

  describe "event stream component" do
    test "displays pause button", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-event-stream")
      |> assert_has("button", text: "Pause")
    end

    test "displays clear button", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has("button", text: "Clear")
    end

    test "displays message count", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-event-count", text: "0 messages")
    end

    test "shows waiting message when no events", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-empty-state-message", text: "Waiting for messages...")
    end

    test "clicking pause changes button text to resume", %{conn: conn} do
      conn
      |> visit("/robot")
      |> click_button("Pause")
      |> assert_has("button", text: "Resume")
    end

    test "shows paused message when paused with no events", %{conn: conn} do
      conn
      |> visit("/robot")
      |> click_button("Pause")
      |> assert_has(".bb-empty-state-message", text: "Paused - no new messages")
    end
  end
end
