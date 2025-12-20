# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.VisualisationTest do
  use BB.LiveView.FeatureCase

  describe "visualisation component" do
    test "renders visualisation container", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-visualisation")
    end

    test "has visualisation hook attached", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has("[phx-hook=Visualisation]")
    end
  end
end
