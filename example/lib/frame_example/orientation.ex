defmodule FrameExample.Orientation do
  @moduledoc """
  Frame orientation from the accelerometer on i2c1 at 0x4c

  The stock device tree calls it an mCube MC3230, but the part on the board
  answers like the MC3419 family: chip ID 0xA0 at register 0x18, and 16-bit
  X/Y/Z (LSB first) at 0x0D-0x12, about 16384 counts per g in the default
  +/-2 g range. Mainline Linux has no driver for it, so this reads it
  directly from `/dev/i2c-1`.

  Standing on its stand in landscape, the frame reads about -1 g on Y.
  """
  use GenServer

  require Logger

  @bus "i2c-1"
  @address 0x4C
  @reg_mode 0x07
  @mode_wake 0x01
  @reg_xout 0x0D
  @counts_per_g 16384
  @poll_ms 250

  # An axis needs this much of gravity before the orientation changes
  @threshold 0.7

  @type orientation ::
          :landscape | :landscape_inverted | :portrait_x_pos | :portrait_x_neg | :flat
  @type acceleration :: %{x: float(), y: float(), z: float()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The current orientation"
  @spec get() :: orientation() | :unknown
  def get(), do: GenServer.call(__MODULE__, :get)

  @doc "The latest reading, in g"
  @spec acceleration() :: acceleration() | nil
  def acceleration(), do: GenServer.call(__MODULE__, :acceleration)

  @impl GenServer
  def init(_opts) do
    with {:ok, i2c} <- Circuits.I2C.open(@bus),
         :ok <- Circuits.I2C.write(i2c, @address, <<@reg_mode, @mode_wake>>) do
      send(self(), :poll)
      {:ok, %{i2c: i2c, orientation: :unknown, acceleration: nil}}
    else
      error ->
        Logger.warning("Orientation: accelerometer not available: #{inspect(error)}")
        :ignore
    end
  end

  @impl GenServer
  def handle_call(:get, _from, state), do: {:reply, state.orientation, state}
  def handle_call(:acceleration, _from, state), do: {:reply, state.acceleration, state}

  @impl GenServer
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_ms)

    case Circuits.I2C.write_read(state.i2c, @address, <<@reg_xout>>, 6) do
      {:ok, <<x::little-signed-16, y::little-signed-16, z::little-signed-16>>} ->
        accel = %{x: x / @counts_per_g, y: y / @counts_per_g, z: z / @counts_per_g}
        orientation = classify(accel, state.orientation)

        if orientation != state.orientation do
          Logger.info("Orientation: #{orientation}")
        end

        {:noreply, %{state | acceleration: accel, orientation: orientation}}

      error ->
        Logger.warning("Orientation: read failed: #{inspect(error)}")
        {:noreply, state}
    end
  end

  # Keep the previous orientation until one axis clearly dominates
  defp classify(%{x: x, y: y, z: z}, previous) do
    cond do
      y <= -@threshold -> :landscape
      y >= @threshold -> :landscape_inverted
      x >= @threshold -> :portrait_x_pos
      x <= -@threshold -> :portrait_x_neg
      abs(z) >= @threshold -> :flat
      true -> previous
    end
  end
end
