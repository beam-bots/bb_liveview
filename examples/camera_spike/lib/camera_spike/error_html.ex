# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule CameraSpike.ErrorHTML do
  @moduledoc """
  The smallest thing that turns an error status into a response.

  Without one, Phoenix raises about a missing template and every 403 or 404
  arrives as a 500 — which is how a CSRF rejection of the dashboard's
  JavaScript spent a while looking like a server fault.
  """

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
