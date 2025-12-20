# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.FeatureCase do
  @moduledoc """
  Test case for feature tests using phoenix_test.

  Provides a unified testing interface for both LiveView and static pages.

  ## Example

      defmodule BB.LiveView.DashboardTest do
        use BB.LiveView.FeatureCase

        test "shows robot name", %{conn: conn} do
          conn
          |> visit("/robot")
          |> assert_has("h1", text: "TestRobot")
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import PhoenixTest

      @endpoint BB.LiveView.TestEndpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
