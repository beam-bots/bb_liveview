# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.LiveView.JointRobot.EffortOnlyActuator do
  @moduledoc """
  A driver that accepts effort commands and nothing else.

  Stands in for a port whose hardware can't be told to go to a position, so
  that the dashboard's handling of a refused slider command can be exercised.
  """
  use BB.Actuator

  alias BB.Message.Actuator.Command

  @impl BB.Actuator
  def command_payloads(_opts), do: [Command.Effort]

  @impl BB.Actuator
  def disarm(_opts), do: :ok

  @impl BB.Actuator
  def init(opts), do: {:ok, %{bb: Keyword.fetch!(opts, :bb)}}

  @impl BB.Actuator
  def handle_command(_message, state), do: {:noreply, state}
end

defmodule BB.LiveView.JointRobot.IgnoredActuator do
  @moduledoc """
  A driver that declines to start, as one does when its hardware is absent.

  Leaves its actuator declared but not running, so that the dashboard's
  handling of a command nothing receives can be exercised.
  """
  use BB.Actuator

  @impl BB.Actuator
  def disarm(_opts), do: :ok

  @impl BB.Actuator
  def init(_opts), do: :ignore

  @impl BB.Actuator
  def handle_command(_message, state), do: {:noreply, state}
end

defmodule BB.LiveView.JointRobot.GatedActuator do
  @moduledoc """
  A driver that holds every command until the test releases it.

  Stands in for a busy bus, so that the dashboard's handling of a command
  that is still pending can be exercised. It can't answer before it is
  released, so the dashboard's timeout always fires first, however long it is.

  Before starting the robot, put the test's pid into persistent term:

      :persistent_term.put({BB.LiveView.JointRobot.GatedActuator, BB.LiveView.JointRobot}, self())

  On receiving a command the driver sends `{:holding, pid, message}` to the
  test and blocks until `pid` is sent `:release`, then sends
  `{:applied, message}`.
  """
  use BB.Actuator

  @impl BB.Actuator
  def disarm(_opts), do: :ok

  @impl BB.Actuator
  def init(opts) do
    bb = Keyword.fetch!(opts, :bb)
    {:ok, %{recipient: :persistent_term.get({__MODULE__, bb.robot})}}
  end

  @impl BB.Actuator
  def handle_command(message, state) do
    send(state.recipient, {:holding, self(), message})

    receive do
      :release -> send(state.recipient, {:applied, message})
    end

    {:noreply, state}
  end
end

defmodule BB.LiveView.JointRobot do
  @moduledoc """
  A robot with a driven joint per way a slider command can fail, for exercising
  the joint control sliders.
  """
  use BB

  settings do
    name(:joint_robot)
  end

  topology do
    link :base_link do
      joint :shoulder do
        type(:revolute)

        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
          effort(~u(10 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        actuator(:motor, BB.LiveView.JointRobot.EffortOnlyActuator)

        sensor(:motor_position, {BB.Sensor.OpenLoopPositionEstimator, actuator: :motor})

        link :arm_link do
          joint :elbow do
            type(:revolute)

            limit do
              lower(~u(-90 degree))
              upper(~u(90 degree))
              effort(~u(10 newton_meter))
              velocity(~u(180 degree_per_second))
            end

            actuator(:slow_motor, BB.LiveView.JointRobot.GatedActuator)

            sensor(
              :slow_motor_position,
              {BB.Sensor.OpenLoopPositionEstimator, actuator: :slow_motor}
            )

            link :forearm_link do
              joint :wrist do
                type(:revolute)

                limit do
                  lower(~u(-90 degree))
                  upper(~u(90 degree))
                  effort(~u(10 newton_meter))
                  velocity(~u(180 degree_per_second))
                end

                actuator(:ignored_motor, BB.LiveView.JointRobot.IgnoredActuator)

                sensor(
                  :ignored_motor_position,
                  {BB.Sensor.OpenLoopPositionEstimator, actuator: :ignored_motor}
                )

                link(:hand_link)
              end
            end
          end
        end
      end
    end
  end
end
