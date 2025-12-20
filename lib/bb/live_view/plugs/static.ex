# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Plugs.Static do
  @moduledoc """
  Serves static assets bundled with the BB LiveView library.

  Assets are served from the library's `priv/static` directory with appropriate
  cache headers based on content hashing.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    file = conn.params["file"]

    case serve_asset(file) do
      {:ok, content, content_type} ->
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, content)
        |> halt()

      :error ->
        conn
        |> send_resp(404, "Not found")
        |> halt()
    end
  end

  defp serve_asset(file) when is_binary(file) do
    # Prevent directory traversal
    if String.contains?(file, "..") or String.contains?(file, "/") do
      :error
    else
      path = Path.join(static_dir(), file)

      if File.exists?(path) do
        {:ok, File.read!(path), content_type(file)}
      else
        :error
      end
    end
  end

  defp serve_asset(_), do: :error

  defp static_dir do
    :bb_liveview
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("static")
  end

  defp content_type(file) do
    case Path.extname(file) do
      ".css" -> "text/css; charset=utf-8"
      ".js" -> "application/javascript; charset=utf-8"
      ".map" -> "application/json"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Returns the path to an asset file for use in templates.

  The path includes a hash of the file contents for cache busting.
  """
  @spec asset_path(String.t()) :: String.t()
  def asset_path(file) do
    hash = asset_hash(file)
    "/__bb_assets__/#{file}?v=#{hash}"
  end

  defp asset_hash(file) do
    path = Path.join(static_dir(), file)

    if File.exists?(path) do
      path
      |> File.read!()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)
    else
      "dev"
    end
  end
end
