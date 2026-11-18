# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.RootRobot do
  @moduledoc """
  A mock robot for the dashboard mounted at the root.

  The case that always worked, kept under test so that making the mounted
  cases work doesn't break it.
  """

  def robot do
    %{
      name: "RootRobot",
      links: %{},
      joints: %{},
      state: :idle
    }
  end
end
