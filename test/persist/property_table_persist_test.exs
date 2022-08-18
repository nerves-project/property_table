defmodule PropertyTablePersistTest do
  use ExUnit.Case

  # @moduletag :capture_log

  @corrupted_table_test_name CorruptTableTest

  setup do
    table_name = :crypto.strong_rand_bytes(8) |> Base.encode16()
    path = System.tmp_dir!()

    [table_name: String.to_atom(table_name), path: path]
  end

  test "PropertyTable.flush_to_disk/1 should save table to disk immediately", %{
    table_name: table,
    path: persist_path
  } do
    {:ok, _pid} = start_supervised({PropertyTable, name: table, persist_data_path: persist_path})

    PropertyTable.flush_to_disk(table)

    # Ensure the file was written
    check_path = Path.join(persist_path, [to_string(table)])
    assert File.exists?(check_path)
  end

  test "PropertyTable.snapshot/1 should save a snapshot to disk", %{
    table_name: table,
    path: persist_path
  } do
    {:ok, _pid} = start_supervised({PropertyTable, name: table, persist_data_path: persist_path})

    {:ok, snapshot_id} = PropertyTable.snapshot(table)

    # Ensure the snapshot was written
    [{found_snapshot_id, _}] = PropertyTable.get_snapshots(table)
    assert found_snapshot_id == snapshot_id
  end

  test "PropertyTable.snapshot/1 should replace the oldest snapshot with a new one when limit is reached",
       %{
         table_name: table,
         path: persist_path
       } do
    {:ok, _pid} =
      start_supervised(
        {PropertyTable, name: table, persist_data_path: persist_path, persist_max_snapshots: 2}
      )

    {:ok, _snapshot_id_0} = PropertyTable.snapshot(table)
    {:ok, snapshot_id_1} = PropertyTable.snapshot(table)
    {:ok, snapshot_id_2} = PropertyTable.snapshot(table)

    assert [
             {^snapshot_id_1, _},
             {^snapshot_id_2, _}
           ] = PropertyTable.get_snapshots(table)
  end

  test "PropertyTable.get_snapshots/1 should return a list of all current snapshots on disk", %{
    table_name: table,
    path: persist_path
  } do
    {:ok, _pid} =
      start_supervised(
        {PropertyTable, name: table, persist_data_path: persist_path, persist_max_snapshots: 5}
      )

    {:ok, _id} = PropertyTable.snapshot(table)
    {:ok, _id} = PropertyTable.snapshot(table)
    {:ok, _id} = PropertyTable.snapshot(table)

    assert length(PropertyTable.get_snapshots(table)) == 3
  end

  test "PropertyTable.restore_snapshot/1 should return a table to a previous snapshot state", %{
    table_name: table,
    path: persist_path
  } do
    {:ok, _pid} =
      start_supervised(
        {PropertyTable, name: table, persist_data_path: persist_path, persist_max_snapshots: 5}
      )

    # set initial property then snapshot
    PropertyTable.put(table, ["property", "test", "a"], :original_value)
    {:ok, snapshot_id} = PropertyTable.snapshot(table)

    # change the property
    PropertyTable.put(table, ["property", "test", "a"], :new_value)

    # restore and check the value
    PropertyTable.restore_snapshot(table, snapshot_id)
    assert PropertyTable.get(table, ["property", "test", "a"]) == :original_value
  end

  test "Calling the persistent/snapshot methods on a non-persistent table will simply noop",
       %{
         table_name: table
       } do
    {:ok, _pid} = start_supervised({PropertyTable, name: table})
    assert PropertyTable.snapshot(table) == :noop
    assert PropertyTable.restore_snapshot(table, "some_id") == :noop
  end

  test "PropertyTable should restore a backup file if present" do
    table = @corrupted_table_test_name
    persist_path = System.tmp_dir!()

    {:ok, pid} = PropertyTable.start_link(name: table, persist_data_path: persist_path)

    # set initial property then snapshot
    PropertyTable.put(table, ["test"], :test_value)
    PropertyTable.flush_to_disk(table)

    Process.exit(pid, :normal)

    stable_path = Path.join(persist_path, ["#{table}", "/prop_table.db"])
    backup_path = Path.join(persist_path, ["#{table}", "/prop_table.db.backup"])

    File.copy!(stable_path, backup_path)

    # "corrupt" the stable file with some random bytes
    random_content = :crypto.strong_rand_bytes(64)
    File.write!(stable_path, random_content, [:binary])

    # Reboot the table, it should restore the backup file
    {:ok, pid} = start_supervised({PropertyTable, name: table, persist_data_path: persist_path})

    assert PropertyTable.get(table, ["test"]) == :test_value
  end
end
