# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.SafetyTest do
  use BB.LiveView.FeatureCase

  describe "safety component" do
    test "displays disarmed state by default", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-safety-disarmed")
      |> assert_has(".bb-safety-text", text: "Disarmed")
    end

    test "arm button is enabled when disarmed", %{conn: conn} do
      conn
      |> visit("/robot")
      |> refute_has("button[disabled]", text: "Arm")
    end

    test "disarm button is disabled when disarmed", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has("button[disabled]", text: "Disarm")
    end

    test "force disarm button is not visible in normal state", %{conn: conn} do
      conn
      |> visit("/robot")
      |> refute_has("button", text: "Force Disarm")
    end

    test "clicking arm with invalid robot shows error message", %{conn: conn} do
      conn
      |> visit("/robot")
      |> click_button("Arm")
      |> assert_has(".bb-error-message", text: "No valid robot connected")
    end
  end
end
