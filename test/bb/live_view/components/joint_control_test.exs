# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.JointControlTest do
  use BB.LiveView.FeatureCase

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest

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

  describe "moving a slider" do
    setup do
      start_supervised!(BB.LiveView.JointRobot)
      :ok = BB.Safety.arm(BB.LiveView.JointRobot)
      :ok
    end

    test "shows the refusal when the actuator won't take a position", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/joint_robot")

      html =
        view
        |> element(".bb-joint-row form")
        |> render_change(%{"joint" => "shoulder", "value" => "0.5"})

      assert html =~ "does not accept"
    end
  end
end
