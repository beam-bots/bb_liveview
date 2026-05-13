# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbLiveview.Install do
    @shortdoc "Installs BB.LiveView dashboard into a Phoenix project"
    @moduledoc """
    #{@shortdoc}

    Imports the package's formatter rules and mounts the BB dashboard inside
    your Phoenix router. If the project has no router (i.e. it isn't a Phoenix
    application), the installer prints a snippet for you to add by hand.

    ## Example

    ```bash
    mix igniter.install bb_liveview
    mix igniter.install bb_liveview --path /robot --robot MyApp.Arm
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    * `--path` - URL path to mount the dashboard at (default `/`).
    """

    use Igniter.Mix.Task

    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Formatter

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [robot: :string, path: :string],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      robot_module = BB.Igniter.robot_module(igniter)
      path = Keyword.get(options, :path, "/")

      igniter = Formatter.import_dep(igniter, :bb_liveview)
      {igniter, router} = Phoenix.select_router(igniter)

      if router do
        mount_dashboard(igniter, router, path, robot_module)
      else
        Igniter.add_notice(igniter, manual_snippet(path, robot_module))
      end
    end

    defp mount_dashboard(igniter, router, path, robot_module) do
      contents = """
      import BB.LiveView.Router
      bb_dashboard #{inspect(path)}, robot: #{inspect(robot_module)}
      """

      Phoenix.append_to_scope(igniter, "/", contents,
        router: router,
        with_pipelines: [:browser]
      )
    end

    defp manual_snippet(path, robot_module) do
      """
      bb_liveview: this project has no Phoenix router. To mount the dashboard,
      add the following to your router inside the `:browser`-piped scope:

          import BB.LiveView.Router
          bb_dashboard #{inspect(path)}, robot: #{inspect(robot_module)}
      """
    end
  end
else
  defmodule Mix.Tasks.BbLiveview.Install do
    @shortdoc "Installs BB.LiveView dashboard into a Phoenix project"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_liveview.install task requires igniter.

          mix igniter.install bb_liveview
      """)

      exit({:shutdown, 1})
    end
  end
end
