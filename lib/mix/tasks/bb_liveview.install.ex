# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbLiveview.Install do
    @shortdoc "Installs BB.LiveView dashboard into a Phoenix project"
    @moduledoc """
    #{@shortdoc}

    Imports the package's formatter rules and mounts the BB dashboard inside
    your Phoenix router.

    If the project has no Phoenix router yet, the installer composes the
    minimal set of `phx_install` sub-tasks needed to support a LiveView
    dashboard — `phx.install.core`, `phx.install.endpoint`,
    `phx.install.router`, `phx.install.live`, `phx.install.assets`. It
    deliberately skips ecto, mailer, gettext, page, dashboard, heroicons, and
    components — robotics projects rarely want them, and `bb_liveview` brings
    its own UI assets.

    ## Example

    ```bash
    mix igniter.install bb_liveview
    mix igniter.install bb_liveview --path /robot --robot MyApp.Arm
    ```

    ## Options

    * `--robot` - The robot module (defaults to `{AppPrefix}.Robot`).
    * `--path` - URL path to mount the dashboard at (default `/`).
    * `--auto-phoenix` - When Phoenix is missing, install it without prompting.
    """

    use Igniter.Mix.Task

    alias Igniter.Code.{Common, Function}
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.{Formatter, Module}

    @bb_assets_path "/__bb_assets__"

    @phoenix_subtasks [
      "phx.install.core",
      "phx.install.endpoint",
      "phx.install.router",
      # `phx.install.live` composes `phx.install.html` for us.
      "phx.install.live",
      "phx.install.assets"
    ]

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: @phoenix_subtasks,
        # phx_install ships the phx.install.* tasks we compose when
        # bootstrapping Phoenix. We declare it via `adds_deps:` (not
        # `installs:`) so the dep lands in the consumer's mix.exs and gets
        # compiled before `igniter/1` runs — without auto-running the
        # opinionated `phx_install.install` orchestrator. Scoped to
        # dev/test to match the `mix igniter.new` default for `:igniter`.
        adds_deps: [{:phx_install, "~> 0.1", only: [:dev, :test], runtime: false}],
        schema: [robot: :string, path: :string, auto_phoenix: :boolean],
        aliases: [r: :robot]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      robot_module = BB.Igniter.robot_module(igniter)
      path = Keyword.get(options, :path, "/")
      auto_phoenix? = Keyword.get(options, :auto_phoenix, false)

      igniter = Formatter.import_dep(igniter, :bb_liveview)
      {igniter, router} = Phoenix.select_router(igniter)

      cond do
        router ->
          mount_dashboard(igniter, router, path, robot_module)

        auto_phoenix? or prompt_phoenix_install?() ->
          bootstrap_phoenix_then_mount(igniter, path, robot_module)

        true ->
          Igniter.add_notice(igniter, manual_snippet(path, robot_module))
      end
    end

    defp mount_dashboard(igniter, router, path, robot_module) do
      contents = """
      import BB.LiveView.Router
      bb_dashboard #{inspect(path)}, robot: #{inspect(robot_module)}
      """

      igniter
      |> Phoenix.append_to_scope("/", contents, router: router, with_pipelines: [:browser])
      |> add_bb_assets_static_plug()
    end

    # Inserts `plug Plug.Static, at: "/__bb_assets__", from: {:bb_liveview,
    # "priv/static"}, gzip: false` into the consumer's endpoint, ahead of the
    # generic `plug Plug.Static`. Serving the bundled JS/CSS at the endpoint
    # level bypasses the router's `:browser` pipeline — otherwise Phoenix's
    # CSRF cross-origin script protection 403s any `<script>` load of
    # `dashboard.js`.
    defp add_bb_assets_static_plug(igniter) do
      endpoint_module = endpoint_module(igniter)

      case Module.find_and_update_module(igniter, endpoint_module, &maybe_insert_plug/1) do
        {:ok, igniter} ->
          igniter

        {:error, igniter} ->
          Igniter.add_warning(igniter, manual_endpoint_snippet(endpoint_module))
      end
    end

    defp maybe_insert_plug(zipper) do
      if bb_assets_plug_exists?(zipper) do
        {:ok, zipper}
      else
        insert_bb_assets_plug(zipper)
      end
    end

    defp manual_endpoint_snippet(endpoint_module) do
      """
      bb_liveview could not find #{inspect(endpoint_module)} to add the static
      plug for `#{@bb_assets_path}`. Add this to your endpoint manually, before
      your other `Plug.Static`:

          plug Plug.Static, at: "#{@bb_assets_path}", from: {:bb_liveview, "priv/static"}, gzip: false
      """
    end

    defp endpoint_module(igniter) do
      Elixir.Module.concat(Phoenix.web_module(igniter), Endpoint)
    end

    defp bb_assets_plug_exists?(zipper) do
      match?({:ok, _}, find_plug_static_for_path(zipper, @bb_assets_path))
    end

    defp insert_bb_assets_plug(zipper) do
      plug_code = """
      plug Plug.Static, at: "#{@bb_assets_path}", from: {:bb_liveview, "priv/static"}, gzip: false
      """

      case find_first_plug_static(zipper) do
        {:ok, target} -> {:ok, Common.add_code(target, plug_code, placement: :before)}
        :error -> {:ok, Common.add_code(zipper, plug_code)}
      end
    end

    defp find_plug_static_for_path(zipper, at_path) do
      Function.move_to_function_call_in_current_scope(zipper, :plug, [2], fn z ->
        Function.argument_equals?(z, 0, Plug.Static) and
          Function.argument_matches_predicate?(z, 1, &keyword_at_equals?(&1, at_path))
      end)
    end

    defp find_first_plug_static(zipper) do
      Function.move_to_function_call_in_current_scope(zipper, :plug, [2], fn z ->
        Function.argument_equals?(z, 0, Plug.Static)
      end)
    end

    defp keyword_at_equals?(zipper, expected) do
      case Igniter.Code.Keyword.get_key(zipper, :at) do
        {:ok, value_zipper} -> Common.nodes_equal?(value_zipper, expected)
        _ -> false
      end
    end

    defp prompt_phoenix_install? do
      Mix.shell().yes?("bb_liveview needs a Phoenix application. Set up a minimal one now?")
    end

    defp bootstrap_phoenix_then_mount(igniter, path, robot_module) do
      igniter
      |> compose_phoenix_subtasks()
      |> mount_after_bootstrap(path, robot_module)
    end

    defp compose_phoenix_subtasks(igniter) do
      Enum.reduce(@phoenix_subtasks, igniter, fn task, igniter ->
        Igniter.compose_task(igniter, task)
      end)
    end

    defp mount_after_bootstrap(igniter, path, robot_module) do
      {igniter, router} = Phoenix.select_router(igniter)

      if router do
        mount_dashboard(igniter, router, path, robot_module)
      else
        igniter
        |> Igniter.add_warning(
          "phx_install did not produce a Phoenix router; mount the dashboard manually."
        )
        |> Igniter.add_notice(manual_snippet(path, robot_module))
      end
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
