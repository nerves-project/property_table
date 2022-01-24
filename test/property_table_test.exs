defmodule PropertyTableTest do
  use ExUnit.Case, async: true

  doctest PropertyTable

  test "start with initial properties", %{test: table} do
    property1 = ["test", "a", "b"]
    property2 = ["test", "c"]

    {:ok, _pid} =
      start_supervised({PropertyTable, properties: [{property1, 1}, {property2, 2}], name: table})

    assert PropertyTable.get(table, property1) == 1
    assert PropertyTable.get(table, property2) == 2
  end

  test "wildcard subscription", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    PropertyTable.subscribe(table, ["a", :_, "c"])

    # Exact match
    PropertyTable.put(table, ["a", "b", "c"], 88)
    assert_receive {^table, ["a", "b", "c"], nil, 88, _}

    # Prefix match
    PropertyTable.put(table, ["a", "b", "c", "d"], 88)
    assert_receive {^table, ["a", "b", "c", "d"], nil, 88, _}

    # No match
    PropertyTable.put(table, ["x", "b", "c"], 88)
    refute_receive {^table, ["x", "b", "c"], _, _, _}

    PropertyTable.put(table, ["a", "b", "d"], 88)
    refute_receive {^table, ["a", "b", "d"], _, _, _}
  end

  test "getting invalid properties returns error", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})

    wildcard_msg =
      "property wildcards can only be used with PropertyTable.subscribe/2 and PropertyTable.match/2"

    # Wildcards aren't allowed
    assert_raise ArgumentError, wildcard_msg, fn -> PropertyTable.get(table, [:_, "a"]) end
    assert_raise ArgumentError, wildcard_msg, fn -> PropertyTable.get(table, [:_]) end

    assert_raise ArgumentError, wildcard_msg, fn ->
      PropertyTable.fetch_with_timestamp(table, [:_])
    end

    assert_raise ArgumentError, wildcard_msg, fn -> PropertyTable.clear(table, [:_]) end
    assert_raise ArgumentError, wildcard_msg, fn -> PropertyTable.clear_prefix(table, [:_]) end

    # Non-string lists aren't allowed
    assert_raise ArgumentError, ~r/is not a string/, fn -> PropertyTable.get(table, ['nope']) end
    assert_raise ArgumentError, ~r/is not a string/, fn -> PropertyTable.get(table, ["a", 5]) end
    assert_raise ArgumentError, ~r/is not a string/, fn -> PropertyTable.get(table, 'nope') end

    # Only strings and lists are allowed
    assert_raise ArgumentError, ~r/is not a valid property/, fn ->
      PropertyTable.get(table, {"a", 5})
    end

    assert_raise ArgumentError, ~r/is not a valid property/, fn ->
      PropertyTable.get(table, :howdy)
    end

    assert_raise ArgumentError, ~r/is not a valid property/, fn ->
      PropertyTable.get(table, %{})
    end

    assert_raise ArgumentError, ~r/is not a valid property/, fn ->
      PropertyTable.get(table, 1234)
    end
  end

  test "sending events", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test"]
    PropertyTable.subscribe(table, property)

    PropertyTable.put(table, property, 99)
    assert_receive {table, ^property, nil, 99, _}

    PropertyTable.put(table, property, 100)
    assert_receive {table, ^property, 99, 100, _}

    PropertyTable.clear(table, property)
    assert_receive {table, ^property, 100, nil, _}

    PropertyTable.unsubscribe(table, property)
  end

  test "setting properties to nil clears them", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test"]

    PropertyTable.put(table, property, 124)
    assert PropertyTable.get_by_prefix(table, []) == [{property, 124}]

    PropertyTable.put(table, property, nil)
    assert PropertyTable.get_by_prefix(table, []) == []
  end

  test "generic subscribers receive events", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]

    PropertyTable.subscribe(table, [])
    PropertyTable.put(table, property, 101)
    assert_receive {table, ^property, nil, 101, _}
    PropertyTable.unsubscribe(table, [])
  end

  test "duplicate events are dropped", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]

    PropertyTable.subscribe(table, property)
    PropertyTable.put(table, property, 102)
    PropertyTable.put(table, property, 102)
    assert_receive {^table, ^property, nil, 102, _}
    refute_receive {^table, ^property, _, 102, _}

    PropertyTable.unsubscribe(table, property)
  end

  test "getting the latest", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]
    assert PropertyTable.get(table, property) == nil

    PropertyTable.put(table, property, 105)
    assert PropertyTable.get(table, property) == 105

    PropertyTable.put(table, property, 106)
    assert PropertyTable.get(table, property) == 106
  end

  test "fetching data with timestamps", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]
    assert :error == PropertyTable.fetch_with_timestamp(table, property)

    PropertyTable.put(table, property, 105)
    now = System.monotonic_time()
    assert {:ok, value, timestamp} = PropertyTable.fetch_with_timestamp(table, property)
    assert value == 105

    # Check that PropertyTable takes the timestamp synchronously.
    # If it doesn't, then this will fail randomly.
    assert now > timestamp

    # Check that it didn't take too long to capture the time
    assert now - timestamp < 1_000_000
  end

  test "getting a subtree", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]
    property2 = ["test", "a", "c"]

    assert PropertyTable.get_by_prefix(table, []) == []

    PropertyTable.put(table, property, 105)
    assert PropertyTable.get_by_prefix(table, []) == [{property, 105}]

    PropertyTable.put(table, property2, 106)
    assert PropertyTable.get_by_prefix(table, []) == [{property, 105}, {property2, 106}]
    assert PropertyTable.get_by_prefix(table, ["test"]) == [{property, 105}, {property2, 106}]

    assert PropertyTable.get_by_prefix(table, ["test", "a"]) == [
             {property, 105},
             {property2, 106}
           ]

    assert PropertyTable.get_by_prefix(table, property) == [{property, 105}]
    assert PropertyTable.get_by_prefix(table, property2) == [{property2, 106}]
  end

  test "clearing a subtree", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    PropertyTable.put(table, ["a", "b", "c"], 1)
    PropertyTable.put(table, ["a", "b", "d"], 2)
    PropertyTable.put(table, ["a", "b", "e"], 3)
    PropertyTable.put(table, ["f", "g"], 4)

    PropertyTable.clear_prefix(table, ["a"])
    assert PropertyTable.get_by_prefix(table, []) == [{["f", "g"], 4}]
  end

  test "match using wildcards", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    PropertyTable.put(table, ["a", "b", "c"], 1)
    PropertyTable.put(table, ["A", "b", "c"], 2)
    PropertyTable.put(table, ["a", "B", "c"], 3)
    PropertyTable.put(table, ["a", "b", "C"], 4)

    # These next properties should never match since we only match on 3 elements below
    PropertyTable.put(table, ["a", "b"], 5)
    PropertyTable.put(table, ["a", "b", "c", "d"], 6)

    # Exact match
    assert PropertyTable.match(table, ["a", "b", "c"]) == [{["a", "b", "c"], 1}]

    # Wildcard one place
    assert PropertyTable.match(table, [:_, "b", "c"]) == [
             {["A", "b", "c"], 2},
             {["a", "b", "c"], 1}
           ]

    assert PropertyTable.match(table, ["a", :_, "c"]) == [
             {["a", "B", "c"], 3},
             {["a", "b", "c"], 1}
           ]

    assert PropertyTable.match(table, ["a", "b", :_]) == [
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]

    # Wildcard two places
    assert PropertyTable.match(table, [:_, :_, "c"]) == [
             {["A", "b", "c"], 2},
             {["a", "B", "c"], 3},
             {["a", "b", "c"], 1}
           ]

    assert PropertyTable.match(table, ["a", :_, :_]) == [
             {["a", "B", "c"], 3},
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]

    # Wildcard three places
    assert PropertyTable.match(table, [:_, :_, :_]) == [
             {["A", "b", "c"], 2},
             {["a", "B", "c"], 3},
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]
  end

  test "timestamp of old and new values are provided in metadata", %{test: table} do
    property = ["a", "b", "c"]

    {:ok, _pid} = start_supervised({PropertyTable, name: table, properties: [{property, 1}]})

    PropertyTable.subscribe(table, property)

    {:ok, 1, old_timestamp} = PropertyTable.fetch_with_timestamp(table, property)

    PropertyTable.put(table, ["a", "b", "c"], 88)

    assert_receive {^table, ["a", "b", "c"], 1, 88, metadata}

    {:ok, 88, new_timestamp} = PropertyTable.fetch_with_timestamp(table, property)

    assert old_timestamp == metadata.old_timestamp
    assert new_timestamp == metadata.new_timestamp
  end

  test "supports string property paths", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    assert :ok = PropertyTable.put(table, "a/b/c", 1)
    assert 1 == PropertyTable.get(table, "a/b/c")
    assert 1 == PropertyTable.get(table, "/a/b/c")
  end

  test "supports string property paths with wildcards", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    assert :ok = PropertyTable.put(table, "a/b/c", 1)
    assert [{["a", "b", "c"], 1}] == PropertyTable.match(table, "a/*/c")
    assert [{["a", "b", "c"], 1}] == PropertyTable.match(table, "/a/*/c")
  end

  test "errors when table does not exist", %{test: table} do
    assert_raise ArgumentError, ~r/unknown registry/, fn ->
      PropertyTable.subscribe(table, ["a"])
    end

    assert_raise ArgumentError, ~r/unknown registry/, fn ->
      PropertyTable.unsubscribe(table, ["a"])
    end

    assert_raise ArgumentError, ~r/does not refer to an existing ETS table/, fn ->
      PropertyTable.get(table, ["a"])
    end

    assert_raise ArgumentError, ~r/does not refer to an existing ETS table/, fn ->
      PropertyTable.fetch_with_timestamp(table, ["a"])
    end

    assert_raise ArgumentError, ~r/does not refer to an existing ETS table/, fn ->
      PropertyTable.get_by_prefix(table, ["a"])
    end

    assert_raise ArgumentError, ~r/does not refer to an existing ETS table/, fn ->
      PropertyTable.match(table, ["a"])
    end

    assert {:noproc, {GenServer, :call, _}} = catch_exit(PropertyTable.put(table, ["a"], 1))
    assert {:noproc, {GenServer, :call, _}} = catch_exit(PropertyTable.clear(table, ["a"]))
    assert {:noproc, {GenServer, :call, _}} = catch_exit(PropertyTable.clear_prefix(table, ["a"]))
  end
end
