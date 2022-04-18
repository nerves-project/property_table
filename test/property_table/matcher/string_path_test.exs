defmodule PropertyTable.Matcher.StringPathTest do
  use ExUnit.Case, async: true

  alias PropertyTable.Matcher.StringPath

  doctest StringPath

  test "check_property/1" do
    assert :ok = StringPath.check_property([])
    assert :ok = StringPath.check_property(["1"])
    assert :ok = StringPath.check_property(["1", "2"])

    assert {:error, _} = StringPath.check_property(nil)
    assert {:error, _} = StringPath.check_property("1")

    assert {:error, _} = StringPath.check_property([:_])
    assert {:error, _} = StringPath.check_property([:"$"])
    assert {:error, _} = StringPath.check_property(["1", :_])
  end

  test "check_pattern/1" do
    assert :ok = StringPath.check_pattern([])
    assert :ok = StringPath.check_pattern(["1"])
    assert :ok = StringPath.check_pattern(["1", "2"])

    assert {:error, _} = StringPath.check_pattern(nil)
    assert {:error, _} = StringPath.check_pattern("1")

    assert :ok = StringPath.check_pattern([:_])
    assert :ok = StringPath.check_pattern([:"$"])
    assert :ok = StringPath.check_pattern(["1", :_])
    assert :ok = StringPath.check_pattern(["1", :"$"])
  end

  test "match/2" do
    assert StringPath.matches?(["1", "2"], ["1", "2"])
    assert StringPath.matches?(["1"], ["1", "2"])
    assert StringPath.matches?([], ["1", "2"])

    assert StringPath.matches?(["1", "2", :"$"], ["1", "2"])
    refute StringPath.matches?(["1", :"$"], ["1", "2"])

    assert StringPath.matches?([:_, "2"], ["1", "2"])
    assert StringPath.matches?(["1", :_], ["1", "2"])
    assert StringPath.matches?([:_, :_], ["1", "2"])
    refute StringPath.matches?([:_, "22"], ["1", "2"])
    refute StringPath.matches?(["11", :_], ["1", "2"])
  end
end
