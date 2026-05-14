# SPDX-FileCopyrightText: 2022 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
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

  describe "match_spec/1 via :ets.select/2" do
    setup do
      %{tbl: :ets.new(:main_table, [:set, :private])}
    end

    test "invalid patterns return :error" do
      assert StringPath.match_spec(nil) == :error
      assert StringPath.match_spec("oops") == :error
      assert StringPath.match_spec([123]) == :error
    end

    test "empty pattern returns every row", %{tbl: tbl} do
      insert_property(tbl, [], :v_empty)
      insert_property(tbl, ["a"], :v_a)
      insert_property(tbl, ["a", "b", "c"], :v_abc)

      assert Enum.sort(match_all(tbl, [])) ==
               [{[], :v_empty}, {["a"], :v_a}, {["a", "b", "c"], :v_abc}]
    end

    test "[:$] returns only the empty property", %{tbl: tbl} do
      insert_property(tbl, [], :v_empty)
      insert_property(tbl, ["a"], :v_a)

      assert match_all(tbl, [:"$"]) == [{[], :v_empty}]
    end

    test "literal prefix returns matching subtree", %{tbl: tbl} do
      insert_property(tbl, ["a"], :v_a)
      insert_property(tbl, ["a", "b"], :v_ab)
      insert_property(tbl, ["a", "b", "c"], :v_abc)
      insert_property(tbl, ["b"], :v_b)

      assert Enum.sort(match_all(tbl, ["a"])) ==
               [{["a"], :v_a}, {["a", "b"], :v_ab}, {["a", "b", "c"], :v_abc}]
    end

    test ":_ wildcard returns any single segment at that position", %{tbl: tbl} do
      insert_property(tbl, ["a", "x"], :v_ax)
      insert_property(tbl, ["a", "y"], :v_ay)
      insert_property(tbl, ["a"], :v_a)
      insert_property(tbl, ["b", "x"], :v_bx)

      assert Enum.sort(match_all(tbl, ["a", :_])) ==
               [{["a", "x"], :v_ax}, {["a", "y"], :v_ay}]
    end

    test "anchored pattern requires exact length", %{tbl: tbl} do
      insert_property(tbl, ["a"], :v_a)
      insert_property(tbl, ["a", "b"], :v_ab)
      insert_property(tbl, ["a", "b", "c"], :v_abc)

      assert match_all(tbl, ["a", "b", :"$"]) == [{["a", "b"], :v_ab}]
    end

    test "parity with matches?/2 for all patterns and properties up to length 3",
         %{tbl: tbl} do
      pattern_segments = ["a", "b", :_, :"$"]
      property_segments = ["a", "b", "c"]

      patterns = Enum.flat_map(0..3, &tuples_of(pattern_segments, &1))
      properties = Enum.flat_map(0..3, &tuples_of(property_segments, &1))

      for property <- properties do
        insert_property(tbl, property, property)
      end

      for pattern <- patterns do
        expected =
          properties
          |> Enum.filter(&StringPath.matches?(pattern, &1))
          |> Enum.map(&{&1, &1})
          |> Enum.sort()

        actual = match_all(tbl, pattern) |> Enum.sort()

        assert expected == actual,
               """
               parity mismatch for pattern #{inspect(pattern)}
                 expected (via StringPath.matches?/2): #{inspect(expected)}
                 actual   (via ETS match-spec):       #{inspect(actual)}
               """
      end
    end
  end

  defp insert_property(tbl, property, value) do
    :ets.insert(tbl, {property, value, 0})
  end

  defp match_all(tbl, pattern) do
    for {property, value, _meta} <- :ets.select(tbl, StringPath.match_spec(pattern)),
        do: {property, value}
  end

  defp tuples_of(_choices, 0), do: [[]]

  defp tuples_of(choices, n) do
    shorter = tuples_of(choices, n - 1)
    for c <- choices, rest <- shorter, do: [c | rest]
  end
end
