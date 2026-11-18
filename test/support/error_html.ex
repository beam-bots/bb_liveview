# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.TestErrorHTML do
  @moduledoc """
  The smallest thing that turns an error status into a response.

  Without one, a 403 or 404 raises `ArgumentError` about a missing template
  and arrives as a 500, which hides the status that actually mattered — a CSRF
  rejection of the dashboard's JavaScript looked like a server fault for
  exactly this reason.
  """

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
