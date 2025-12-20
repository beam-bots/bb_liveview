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
end
