# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.Components.ParametersTest do
  use BB.LiveView.FeatureCase

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest

  alias BB.LiveView.ParameterRobot
  alias BB.Parameter

  describe "parameters component" do
    test "renders parameters container", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-parameters")
    end

    test "shows no parameters message when robot has no parameters", %{conn: conn} do
      conn
      |> visit("/robot")
      |> assert_has(".bb-empty-state-message", text: "No parameters defined")
    end
  end

  describe "unit-typed parameters" do
    setup do
      start_supervised!(ParameterRobot)
      :ok
    end

    test "renders a bounded parameter as a slider over its magnitudes", %{conn: conn} do
      conn
      |> visit("/parameter_robot")
      |> assert_has(
        ~s([id="slider-motion.trim"] input[type="range"][min="-30"][max="30"][step="0.6"][value="0"])
      )
      |> assert_has(~s([id="slider-motion.trim"] .bb-unit-label), text: "degree")
    end

    test "renders an unbounded parameter as its magnitude", %{conn: conn} do
      conn
      |> visit("/parameter_robot")
      |> assert_has(~s(.bb-number-input input[value="0.5"]))
      |> assert_has(".bb-number-input .bb-unit-label", text: "meter")
    end

    test "shows a value stored in a compatible unit in the declared unit", %{conn: conn} do
      radians = Localize.Unit.new!(0.26, "radian")
      :ok = Parameter.set(ParameterRobot, [:motion, :trim], radians)

      degrees = Localize.Unit.convert!(radians, "degree")

      conn
      |> visit("/parameter_robot")
      |> assert_has(~s([id="slider-motion.trim"] input[value="#{degrees.value}"]))
      |> assert_has(~s([id="slider-motion.trim"] .bb-unit-label), text: "degree")
    end

    test "writes the edited magnitude back in the declared unit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/parameter_robot")
      render(view)

      view
      |> element(~s([id="slider-motion.trim"] input[type="number"]))
      |> render_change(%{"path" => "motion.trim", "value" => "15"})

      assert {:ok, %Localize.Unit{value: 15.0, name: "degree"}} =
               Parameter.get(ParameterRobot, [:motion, :trim])
    end
  end

  describe "refused writes" do
    setup do
      start_supervised!(ParameterRobot)
      :ok
    end

    test "shows the refusal rather than swallowing it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/parameter_robot")
      render(view)

      html =
        view
        |> element(~s([id="slider-motion.trim"] input[type="number"]))
        |> render_change(%{"path" => "motion.trim", "value" => "45"})

      assert html =~ "less than or equal to 30 degree"
    end

    test "clears the refusal once a write is accepted", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/parameter_robot")
      render(view)

      input = element(view, ~s([id="slider-motion.trim"] input[type="number"]))

      render_change(input, %{"path" => "motion.trim", "value" => "45"})
      html = render_change(input, %{"path" => "motion.trim", "value" => "15"})

      refute html =~ "bb-error-message"
    end
  end
end
