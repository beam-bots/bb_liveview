# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.NestedRobot do
  @moduledoc """
  A mock robot for the dashboard mounted inside an outer scope.

  A distinct module from `BB.LiveView.TestRobot` because `bb_dashboard/2`
  names its `live_session` after the robot, so one robot cannot currently be
  mounted twice.
  """

  def robot do
    %{
      name: "NestedRobot",
      links: %{},
      joints: %{},
      state: :idle
    }
  end
end
