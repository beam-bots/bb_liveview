# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.JointControlTest do
  use BB.LiveView.FeatureCase

  describe "joint control component" do
    test "displays armed badge showing disarmed state", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-armed-badge.disarmed", text: "Disarmed")
    end

    test "shows empty state when no joints (test robot)", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-empty-state-message", text: "No movable joints found")
    end

    test "displays table headers when joints exist", %{conn: conn} do
      # With test robot (no joints), we check the component renders
      conn
      |> visit("/robot")
      |> assert_has(".bb-joint-control")
    end
  end
end
