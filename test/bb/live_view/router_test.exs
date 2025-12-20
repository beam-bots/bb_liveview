# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.RouterTest do
  use BB.LiveView.ConnCase

  describe "bb_dashboard/2 macro" do
    test "generates routes at the specified path", %{conn: conn} do
      conn = get(conn, "/robot")
      assert html_response(conn, 200)
    end

    test "serves asset routes", %{conn: conn} do
      conn = get(conn, "/robot/__bb_assets__/dashboard.css")
      assert response(conn, 200)
      assert response_content_type(conn, :css)
    end

    test "returns 404 for non-existent assets", %{conn: conn} do
      conn = get(conn, "/robot/__bb_assets__/nonexistent.css")
      assert response(conn, 404)
    end
  end
end
