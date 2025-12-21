# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbLiveview.Install do
    @shortdoc "Installs BB.LiveView into a Phoenix project"
    @moduledoc """
    #{@shortdoc}

    Adds the BB dashboard route to your Phoenix router and configures the endpoint
    to serve BB.LiveView's static assets.

    ## Example

    ```bash
    mix igniter.install bb_liveview
    ```

    ## What This Does

    1. Adds `import BB.LiveView.Router` to your router
    2. Adds `bb_dashboard "/robot", robot: YourApp.Robot` to a browser scope
    3. Adds `Plug.Static` to your endpoint for serving BB.LiveView assets
    """

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Module

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      robot_module = Module.module_name(igniter, "Robot")

      igniter
      |> setup_router(robot_module)
      |> setup_endpoint()
    end

    defp setup_router(igniter, robot_module) do
      {igniter, router} = Phoenix.select_router(igniter)

      if router do
        igniter
        |> add_router_import(router)
        |> Phoenix.append_to_scope(
          "/",
          "bb_dashboard \"/robot\", robot: #{inspect(robot_module)}",
          router: router,
          with_pipelines: [:browser]
        )
      else
        Igniter.add_warning(
          igniter,
          "No Phoenix router found. Please add the following manually:\n\n" <>
            "  import BB.LiveView.Router\n\n" <>
            "  scope \"/\" do\n" <>
            "    pipe_through :browser\n" <>
            "    bb_dashboard \"/robot\", robot: #{inspect(robot_module)}\n" <>
            "  end"
        )
      end
    end

    defp add_router_import(igniter, router) do
      Module.find_and_update_module!(igniter, router, fn zipper ->
        case Phoenix.move_to_router_use(igniter, zipper) do
          {:ok, zipper} -> {:ok, Common.add_code(zipper, "import BB.LiveView.Router")}
          :error -> {:ok, zipper}
        end
      end)
    end

    defp setup_endpoint(igniter) do
      {igniter, endpoint} = Phoenix.select_endpoint(igniter)

      if endpoint do
        Module.find_and_update_module!(igniter, endpoint, &add_static_plug/1)
      else
        Igniter.add_warning(
          igniter,
          "No Phoenix endpoint found. Please add the following manually:\n\n" <>
            "  plug Plug.Static,\n" <>
            "    at: \"/__bb_assets__\",\n" <>
            "    from: {:bb_liveview, \"priv/static\"},\n" <>
            "    gzip: false"
        )
      end
    end

    defp add_static_plug(zipper) do
      plug_code = """
      plug Plug.Static,
        at: "/__bb_assets__",
        from: {:bb_liveview, "priv/static"},
        gzip: false
      """

      case Function.move_to_function_call_in_current_scope(
             zipper,
             :plug,
             [1, 2],
             &Function.argument_equals?(&1, 0, Plug.RequestId)
           ) do
        {:ok, zipper} -> {:ok, Common.add_code(zipper, plug_code, placement: :before)}
        :error -> {:ok, Common.add_code(zipper, plug_code)}
      end
    end
  end
else
  defmodule Mix.Tasks.BbLiveview.Install do
    @shortdoc "Installs BB.LiveView into a Phoenix project"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_liveview.install task requires igniter. Please install igniter and try again.

          mix igniter.install bb_liveview
      """)

      exit({:shutdown, 1})
    end
  end
end
