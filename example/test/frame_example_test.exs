defmodule FrameExampleTest do
  use ExUnit.Case
  doctest FrameExample

  test "greets the world" do
    assert FrameExample.hello() == :world
  end
end
