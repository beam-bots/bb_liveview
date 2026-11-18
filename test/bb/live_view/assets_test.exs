# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.AssetsTest do
  @moduledoc """
  The dashboard's own bundle, fetched the way a browser fetches it.

  These tests take the `href` and `src` out of the rendered page and request
  exactly those URLs through the same endpoint, because the failure they exist
  to catch is a mismatch between what the layout writes and where the router
  serves: a dashboard mounted anywhere but `/` used to render root-absolute
  asset URLs and 404 both files, leaving a dashboard with no stylesheet and no
  JavaScript.
  """

  use BB.LiveView.ConnCase

  setup %{conn: conn} do
    # `Phoenix.ConnTest.build_conn/0` sets `:plug_skip_csrf_protection`, which
    # is why every earlier test fetched the bundle happily while a browser got
    # a 403: `Plug.CSRFProtection` refuses a non-XHR GET whose *response* is
    # JavaScript, and the test harness had switched that check off. These tests
    # put it back, and send no `x-requested-with`, so they ask for the bundle
    # the way a `<script>` tag does.
    {:ok, conn: put_private(conn, :plug_skip_csrf_protection, false)}
  end

  describe "a dashboard at the root" do
    test "serves the CSS it asks for", %{conn: conn} do
      assert_serves(conn, "/", stylesheet_url(conn, "/"), :css, "bb-dashboard")
    end

    test "serves the JavaScript it asks for", %{conn: conn} do
      assert_serves(conn, "/", script_url(conn, "/"), :js, "phx")
    end
  end

  describe "a dashboard mounted under a path" do
    test "addresses its assets under that path", %{conn: conn} do
      assert script_url(conn, "/robot") =~ ~r{^/robot/__bb_assets__/dashboard\.js\?v=}
      assert stylesheet_url(conn, "/robot") =~ ~r{^/robot/__bb_assets__/dashboard\.css\?v=}
    end

    test "serves the CSS it asks for", %{conn: conn} do
      assert_serves(conn, "/robot", stylesheet_url(conn, "/robot"), :css, "bb-dashboard")
    end

    test "serves the JavaScript it asks for", %{conn: conn} do
      assert_serves(conn, "/robot", script_url(conn, "/robot"), :js, "phx")
    end
  end

  describe "a dashboard inside an outer scope" do
    test "learns the outer path from the request, not the macro", %{conn: conn} do
      assert script_url(conn, "/admin/arm") =~ ~r{^/admin/arm/__bb_assets__/dashboard\.js\?v=}
    end

    test "serves the CSS it asks for", %{conn: conn} do
      assert_serves(conn, "/admin/arm", stylesheet_url(conn, "/admin/arm"), :css, "bb-dashboard")
    end

    test "serves the JavaScript it asks for", %{conn: conn} do
      assert_serves(conn, "/admin/arm", script_url(conn, "/admin/arm"), :js, "phx")
    end
  end

  describe "several dashboards at once" do
    test "each references its own mount rather than the first one", %{conn: conn} do
      assert script_url(conn, "/robot") =~ "/robot/__bb_assets__/"
      assert script_url(conn, "/joint_robot") =~ "/joint_robot/__bb_assets__/"
      assert script_url(conn, "/admin/arm") =~ "/admin/arm/__bb_assets__/"
    end
  end

  describe "the CSRF exemption" do
    test "is on the asset route", %{conn: conn} do
      conn = get(conn, script_url(conn, "/robot"))

      assert conn.private[:plug_skip_csrf_protection] == true
    end

    test "is not on the camera stream, which can carry a view of the room", %{conn: conn} do
      conn = get(conn, "/robot/__bb_camera__/nostril/mjpeg")

      refute conn.private[:plug_skip_csrf_protection]
    end

    test "is not on the dashboard itself", %{conn: conn} do
      conn = get(conn, "/robot")

      refute conn.private[:plug_skip_csrf_protection]
    end
  end

  describe "the cache-busting hash" do
    test "survives the round trip and is the same for one file", %{conn: conn} do
      ["v=" <> hash] = Regex.run(~r/v=([0-9a-f]+)/, script_url(conn, "/robot"), capture: :first)

      assert String.length(hash) == 8
      assert script_url(conn, "/admin/arm") =~ hash
    end
  end

  # Both halves matter. The URL has to sit under the page's own mount — the
  # test router also mounts a dashboard at the root, whose asset route would
  # otherwise answer a root-absolute URL and hide the mismatch, exactly as an
  # endpoint-level `Plug.Static` does in an installed application. And the
  # fetch has to come back as the file, not merely as a 200.
  defp assert_serves(conn, page, url, type, body_fragment) do
    assert String.starts_with?(url, Path.join(page, "__bb_assets__")),
           "#{page} asks for #{url}, which is not under its own mount"

    response = get(conn, url)

    assert response.status == 200,
           "#{page} asks for #{url}, which answered #{response.status}"

    assert response_content_type(response, type)
    assert response.resp_body =~ body_fragment
    assert byte_size(response.resp_body) > 0
  end

  defp render_dashboard(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
  end

  defp script_url(conn, path) do
    conn
    |> render_dashboard(path)
    |> extract(~r/<script[^>]+src="([^"]+)"/)
  end

  defp stylesheet_url(conn, path) do
    conn
    |> render_dashboard(path)
    |> extract(~r/<link[^>]+href="([^"]+)"/)
  end

  defp extract(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [url] -> url
      nil -> flunk("no asset URL matching #{inspect(regex)} in the rendered page")
    end
  end
end
