# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.ParametersTest do
  use BB.LiveView.FeatureCase

  describe "parameters component" do
    test "renders parameters container", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-parameters")
    end

    test "shows no parameters message when robot has no parameters", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-empty-state-message", text: "No parameters defined")
    end
  end
end
