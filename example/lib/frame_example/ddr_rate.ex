defmodule FrameExample.DdrRate do
  @moduledoc """
  Raises the DDR rate from the loader's 332 MHz to 400 MHz, the stock rate

  The kernel's PX30 DMC driver starts with the userspace governor and
  leaves the rate alone, so a fresh boot always runs at the loader's rate.
  This waits until the running firmware is validated before switching, so
  a firmware that misbehaves at 400 MHz can still fall back on its own, and
  a power cycle always brings back 332 MHz.
  """
  use Task, restart: :transient

  require Logger

  @devfreq "/sys/class/devfreq/dmc"
  @rate_hz 400_000_000
  @check_ms 5_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    Task.start_link(__MODULE__, :run, [Keyword.get(opts, :rate_hz, @rate_hz)])
  end

  @doc false
  @spec run(pos_integer()) :: :ok
  def run(rate_hz) do
    if File.exists?(Path.join(@devfreq, "userspace/set_freq")) do
      wait_until_valid()
      set_rate(rate_hz)
    else
      Logger.info("DdrRate: no DMC devfreq with the userspace governor, leaving DDR alone")
    end
  end

  defp wait_until_valid() do
    unless Nerves.Runtime.firmware_valid?() do
      Process.sleep(@check_ms)
      wait_until_valid()
    end
  end

  defp set_rate(rate_hz) do
    case File.write(Path.join(@devfreq, "userspace/set_freq"), Integer.to_string(rate_hz)) do
      :ok ->
        cur = @devfreq |> Path.join("cur_freq") |> File.read!() |> String.trim()
        Logger.info("DdrRate: DDR now at #{cur} Hz")

      {:error, reason} ->
        Logger.warning("DdrRate: couldn't set DDR to #{rate_hz} Hz: #{inspect(reason)}")
    end
  end
end
