# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.CommandTest do
  use BB.LiveView.FeatureCase

  describe "command component" do
    test "displays no commands message when robot has no commands", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-command")
      |> assert_has(".bb-empty-state-message", text: "No commands available")
    end
  end

  describe "continuous commands" do
    setup do
      start_supervised!(BB.LiveView.CommandRobot)
      :ok
    end

    test "shows a cancel control while running and cancels on demand", %{conn: conn} do
      conn
      |> visit("/command_robot")
      |> assert_has(".bb-command-name", text: "run_forever")
      |> click_button("Execute")
      |> assert_has("button", text: "Running")
      |> assert_has(".bb-button-danger", text: "Cancel")
      |> click_button("Cancel")
      |> assert_has(".bb-command-result.error", text: "cancelled", timeout: 1000)
      |> refute_has("button", text: "Running")
    end
  end
end
