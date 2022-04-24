defmodule PropertyTableTest do
  use ExUnit.Case, async: true

  alias PropertyTable.Event

  doctest PropertyTable

  test "start with initial properties", %{test: table} do
    property1 = ["test", "a", "b"]
    property2 = ["test", "c"]

    {:ok, _pid} =
      start_supervised({PropertyTable, properties: [{property1, 1}, {property2, 2}], name: table})

    assert PropertyTable.get(table, property1) == 1
    assert PropertyTable.get(table, property2) == 2
  end

  test "clearing properties", %{test: table} do
    property1 = ["test", "a", "b"]
    property2 = ["test", "c"]

    {:ok, _pid} =
      start_supervised({PropertyTable, properties: [{property1, 1}, {property2, 2}], name: table})

    assert PropertyTable.get(table, property1) == 1
    PropertyTable.clear(table, property1)
    assert PropertyTable.get(table, property1) == nil

    # Redundant clear does nothing
    PropertyTable.clear(table, property1)

    assert PropertyTable.get_all(table) == [{property2, 2}]
  end

  test "crashing table doesn't lose properties", %{test: table} do
    property1 = ["test", "a"]
    property2 = ["test", "b"]
    property3 = ["test", "c"]

    {:ok, _pid} =
      start_supervised({PropertyTable, properties: [{property1, 1}, {property2, 2}], name: table})

    # Change a seed property and add a new property
    PropertyTable.put(table, property2, 22)
    PropertyTable.put(table, property3, 33)

    # Check that we set the table up for the test correctly
    assert PropertyTable.get(table, property1) == 1
    assert PropertyTable.get(table, property2) == 22
    assert PropertyTable.get(table, property3) == 33

    # Crash the table. Due to async process crash and recovery if there isn't a
    # sleep here, the asserts can run before the crash and pass without testing
    # recovery.
    table_genserver = PropertyTable.Table.server_name(table)
    Process.exit(Process.whereis(table_genserver), :oops)
    Process.sleep(10)

    # Test that the properties didn't get lost or overwritten
    assert PropertyTable.get(table, property1) == 1
    assert PropertyTable.get(table, property2) == 22
    assert PropertyTable.get(table, property3) == 33
  end

  test "wildcard subscription", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    PropertyTable.subscribe(table, ["a", :_, "c"])

    # Exact match
    PropertyTable.put(table, ["a", "b", "c"], 7)
    assert_receive %Event{table: ^table, property: ["a", "b", "c"], value: 7, previous_value: nil}

    # Prefix match
    PropertyTable.put(table, ["a", "b", "c", "d"], 8)

    assert_receive %Event{
      table: ^table,
      property: ["a", "b", "c", "d"],
      value: 8,
      previous_value: nil
    }

    # No match
    PropertyTable.put(table, ["x", "b", "c"], 9)
    refute_receive _

    PropertyTable.put(table, ["a", "b", "d"], 10)
    refute_receive _
  end

  test "sending events", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test"]
    PropertyTable.subscribe(table, property)

    PropertyTable.put(table, property, 99)
    assert_receive %Event{table: ^table, property: ^property, value: 99, previous_value: nil}

    PropertyTable.put(table, property, 100)
    assert_receive %Event{table: ^table, property: ^property, value: 100, previous_value: 99}

    PropertyTable.clear(table, property)
    assert_receive %Event{table: ^table, property: ^property, value: nil, previous_value: 100}

    PropertyTable.unsubscribe(table, property)

    PropertyTable.put(table, property, 102)
    refute_receive _
  end

  test "properties can be set to nil", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test"]

    PropertyTable.put(table, property, nil)
    assert PropertyTable.get_all(table) == [{property, nil}]
  end

  test "subscribing from one process to multiple patterns", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property1 = ["test1"]
    property2 = ["test2"]
    property3 = ["test3"]
    PropertyTable.subscribe(table, property1)
    PropertyTable.subscribe(table, property2)

    # Check that both subscriptions work
    PropertyTable.put(table, property1, 99)
    assert_receive %Event{table: ^table, property: ^property1, value: 99, previous_value: nil}

    PropertyTable.put(table, property2, 100)
    assert_receive %Event{table: ^table, property: ^property2, value: 100, previous_value: nil}

    PropertyTable.put(table, property3, 101)
    refute_receive _

    # Check that unsubscribing to one doesn't stop notifications to the other
    PropertyTable.unsubscribe(table, property1)

    PropertyTable.clear(table, property1)
    refute_receive _
    PropertyTable.put(table, property2, 102)
    assert_receive %Event{table: ^table, property: ^property2, value: 102, previous_value: 100}

    PropertyTable.unsubscribe(table, property2)
    PropertyTable.clear(table, property2)
    refute_receive _
  end

  test "generic subscribers receive events", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]

    PropertyTable.subscribe(table, [])
    PropertyTable.put(table, property, 101)
    assert_receive %Event{table: ^table, property: ^property, value: 101}
    PropertyTable.unsubscribe(table, [])

    PropertyTable.put(table, property, 101)
    refute_receive _
  end

  test "duplicate events are dropped", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]

    PropertyTable.subscribe(table, property)
    PropertyTable.put(table, property, 102)
    PropertyTable.put(table, property, 102)
    assert_receive %Event{table: ^table, property: ^property, value: 102}
    refute_receive _

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

  defp deterministic_match(table, pattern) do
    # The match order isn't deterministic across OTP versions, so sort it.
    PropertyTable.match(table, pattern) |> Enum.sort()
  end

  test "matching a subtree", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    property = ["test", "a", "b"]
    property2 = ["test", "a", "c"]

    assert PropertyTable.match(table, []) == []

    PropertyTable.put(table, property, 105)
    assert PropertyTable.match(table, []) == [{property, 105}]

    PropertyTable.put(table, property2, 106)
    assert deterministic_match(table, []) == [{property, 105}, {property2, 106}]
    assert deterministic_match(table, ["test"]) == [{property, 105}, {property2, 106}]

    assert deterministic_match(table, ["test", "a"]) == [
             {property, 105},
             {property2, 106}
           ]

    assert PropertyTable.match(table, property) == [{property, 105}]
    assert PropertyTable.match(table, property2) == [{property2, 106}]
  end

  test "clearing a subtree", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    PropertyTable.put(table, ["a", "b", "c"], 1)
    PropertyTable.put(table, ["a", "b", "d"], 2)
    PropertyTable.put(table, ["a", "b", "e"], 3)
    PropertyTable.put(table, ["f", "g"], 4)

    PropertyTable.clear_all(table, ["a"])
    assert PropertyTable.get_all(table) == [{["f", "g"], 4}]
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
    assert deterministic_match(table, ["a", "b", "c", :"$"]) == [{["a", "b", "c"], 1}]

    # Wildcard one place
    assert deterministic_match(table, [:_, "b", "c", :"$"]) == [
             {["A", "b", "c"], 2},
             {["a", "b", "c"], 1}
           ]

    assert deterministic_match(table, ["a", :_, "c", :"$"]) == [
             {["a", "B", "c"], 3},
             {["a", "b", "c"], 1}
           ]

    assert deterministic_match(table, ["a", "b", :_, :"$"]) == [
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]

    # Wildcard two places
    assert deterministic_match(table, [:_, :_, "c", :"$"]) == [
             {["A", "b", "c"], 2},
             {["a", "B", "c"], 3},
             {["a", "b", "c"], 1}
           ]

    assert deterministic_match(table, ["a", :_, :_, :"$"]) == [
             {["a", "B", "c"], 3},
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]

    # Wildcard three places
    assert deterministic_match(table, [:_, :_, :_, :"$"]) == [
             {["A", "b", "c"], 2},
             {["a", "B", "c"], 3},
             {["a", "b", "C"], 4},
             {["a", "b", "c"], 1}
           ]
  end

  test "timestamp of old and new values are provided", %{test: table} do
    property = ["a", "b", "c"]

    {:ok, _pid} = start_supervised({PropertyTable, name: table, properties: [{property, 1}]})

    PropertyTable.subscribe(table, property)

    {:ok, 1, previous_timestamp} = PropertyTable.fetch_with_timestamp(table, property)

    PropertyTable.put(table, ["a", "b", "c"], 88)

    assert_receive %Event{
      table: ^table,
      property: ["a", "b", "c"],
      value: 88,
      previous_value: 1,
      timestamp: event_timestamp,
      previous_timestamp: event_previous_timestamp
    }

    {:ok, 88, timestamp} = PropertyTable.fetch_with_timestamp(table, property)

    assert previous_timestamp == event_previous_timestamp
    assert timestamp == event_timestamp
  end

  test "sending the old tuple events", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table, tuple_events: true})
    property = ["test", "a", "b"]

    PropertyTable.subscribe(table, [])
    PropertyTable.put(table, property, 101)
    assert_receive {^table, ^property, nil, 101, %{old_timestamp: _, new_timestamp: _}}
  end

  test "rejects bad properties", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})

    PropertyTable.subscribe(table, [])

    # Bad property raises
    assert_raise ArgumentError, fn -> PropertyTable.put(table, [:bad], 90) end

    # Doesn't send event
    refute_receive _

    # Isn't in table
    assert PropertyTable.get_all(table) == []
  end

  test "rejects bad subscriptions", %{test: table} do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})

    assert_raise ArgumentError, fn -> PropertyTable.subscribe(table, :bad) end
  end
end
