# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.ConnCase do
  @moduledoc """
  Test case for connection-based tests.

  Provides helpers for testing controllers and plugs.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import BB.LiveView.ConnCase

      @endpoint BB.LiveView.TestEndpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
