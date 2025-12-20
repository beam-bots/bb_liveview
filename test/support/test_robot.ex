# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.TestRobot do
  @moduledoc """
  A mock robot module for testing the BB Dashboard.
  """

  def robot do
    %{
      name: "TestRobot",
      links: %{},
      joints: %{},
      state: :idle
    }
  end
end
