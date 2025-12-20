# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

Application.ensure_all_started(:mimic)

# Start the test endpoint
{:ok, _} = Application.ensure_all_started(:phoenix)
{:ok, _} = BB.LiveView.TestEndpoint.start_link()

ExUnit.start()
