defmodule PropertyTable.MatcherTest do
  use ExUnit.Case, async: true

  alias PropertyTable.Matcher

  doctest Matcher

  test "check_property/1" do
    assert :ok = Matcher.check_property([])
    assert :ok = Matcher.check_property(["1"])
    assert :ok = Matcher.check_property(["1", "2"])

    assert {:error, _} = Matcher.check_property(nil)
    assert {:error, _} = Matcher.check_property("1")

    assert {:error, _} = Matcher.check_property([:_])
    assert {:error, _} = Matcher.check_property([:"$"])
    assert {:error, _} = Matcher.check_property(["1", :_])
  end

  test "check_pattern/1" do
    assert :ok = Matcher.check_pattern([])
    assert :ok = Matcher.check_pattern(["1"])
    assert :ok = Matcher.check_pattern(["1", "2"])

    assert {:error, _} = Matcher.check_pattern(nil)
    assert {:error, _} = Matcher.check_pattern("1")

    assert :ok = Matcher.check_pattern([:_])
    assert :ok = Matcher.check_pattern([:"$"])
    assert :ok = Matcher.check_pattern(["1", :_])
    assert :ok = Matcher.check_pattern(["1", :"$"])
  end

  test "match/2" do
    assert Matcher.match?(["1", "2"], ["1", "2"])
    assert Matcher.match?(["1"], ["1", "2"])
    assert Matcher.match?([], ["1", "2"])

    assert Matcher.match?(["1", "2", :"$"], ["1", "2"])
    refute Matcher.match?(["1", :"$"], ["1", "2"])

    assert Matcher.match?([:_, "2"], ["1", "2"])
    assert Matcher.match?(["1", :_], ["1", "2"])
    assert Matcher.match?([:_, :_], ["1", "2"])
    refute Matcher.match?([:_, "22"], ["1", "2"])
    refute Matcher.match?(["11", :_], ["1", "2"])
  end
end
