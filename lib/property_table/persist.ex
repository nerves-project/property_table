defmodule PropertyTable.Persist do
  @moduledoc """
  This module contains logic to persist the content of a PropertyTable to disk

  It does so in the following manner:

  1. If a `prop_table.db` file exists in the data directory, rename it to `prop_table.db.backup`
  2. Write the data of the ETS table to the file `prop_table.db`
  3. Delete the backup file

  When you wish to restore a property table from disk, the following will occur:

  1. The stable file will be verified, if it validates, it will be loaded
  2. If the stable file failed to validate or did not exist, try and load from the last backup file
  3. If the backup file fails, log loudly about data loss

  You can also manually request "snapshots" of the property table, this will immediately do the procedure for persisting to disk above, then a duplicate of the
  current `prop_table.db` file will be copied into the `snapshots/` directory with a timestamp added to the file name. `max_snapshots` in the options keyword list can be used
  to limit the number of snapshots saved in the `snapshots/` directory, if the limit is reached during a snapshot operation, the oldest snapshot will be deleted from disk.
  """

  require Logger

  alias PropertyTable.PersistFile

  # Options for persisting to disk, and their default values
  @persist_options %{
    data_directory: "/tmp/property_table",
    table_name: nil,
    max_snapshots: 25,
    compression: 6
  }

  @data_stable_name "data.ptable"
  @data_backup_name "data.ptable.backup"

  @spec persist_to_disk(reference() | atom(), Keyword.t()) :: :ok | :error | no_return()
  def persist_to_disk(table, options) do
    options = take_options(options)

    stable_path = get_path(:stable, options)
    backup_path = get_path(:backup, options)

    if File.exists?(stable_path) do
      # Move the current stable data file to the backup path
      Logger.debug("Moving stable data file to backup: #{stable_path} => #{backup_path}")
      File.rename!(stable_path, backup_path)
    end

    Logger.debug("Writing PropertyTable to #{stable_path}")

    dump = PropertyTable.get_all(table)
    binary_data = :erlang.term_to_binary(dump, compressed: options[:compression])
    encoded = PersistFile.encode_binary(binary_data)

    File.write!(stable_path, encoded, [:binary, :sync])

    :ok
  rescue
    e ->
      Logger.error("Failed to persist table to disk: #{e}")
      :error
  end

  @spec restore_from_disk(reference() | atom(), Keyword.t()) :: :ok | {:error, atom()}
  def restore_from_disk(table, options) do
    options = take_options(options)

    stable_path = get_path(:stable, options)
    backup_path = get_path(:backup, options)

    # Reduce over all the possible paths we want to try and restore from
    attempts = [stable_path, backup_path]

    result =
      Enum.reduce_while(attempts, {:error, :failed_to_load}, fn path, _ ->
        if File.exists?(path) do
          try_restore_tabfile(path)
        else
          Logger.warning("File #{path} does not exist! Trying a backup file...")
          {:cont, {:error, :enoent}}
        end
      end)

    case result do
      {:ok, data} ->
        ^table = :ets.new(table, [:named_table, :public])

        # Insert the restored properties at the current timestamp
        timestamp = System.monotonic_time()

        Enum.each(data, fn {property, value} ->
          :ets.insert(table, {property, value, timestamp})
        end)

        :ok

      error ->
        error
    end
  rescue
    e ->
      Logger.error("Failed to restore table from disk: #{e}")
      {:error, :failed_to_restore}
  end

  @spec save_snapshot(reference() | atom(), Keyword.t()) ::
          {:ok, String.t()} | :error | no_return()
  def save_snapshot(table, options) do
    options = take_options(options)
    persist_to_disk(table, options)

    snapshot_id = :crypto.strong_rand_bytes(8) |> Base.encode16()

    full_snapshot_name = "#{snapshot_id}"
    stable_path = get_path(:stable, options)
    snapshot_path = get_path(:snapshot, options, full_snapshot_name)

    # Move file to snapshot directory
    Logger.debug("Creating table file snapshot: #{snapshot_path}")
    File.copy!(stable_path, snapshot_path)

    maybe_clean_old_snapshots(options)

    {:ok, snapshot_id}
  rescue
    e ->
      Logger.error("Failed to save snapshot to disk: #{e}")
      :error
  end

  @spec restore_snapshot(Keyword.t(), String.t()) :: :ok | {:error, atom()} | no_return()
  def restore_snapshot(options, snapshot_id) do
    options = take_options(options)
    stable_path = get_path(:stable, options)
    snapshot_path = get_path(:snapshot, options) |> Path.join(snapshot_id)

    case PersistFile.decode_file(snapshot_path) do
      {:ok, _content} ->
        Logger.debug("Restoring table file snapshot: #{snapshot_path} => #{stable_path}")
        File.copy!(snapshot_path, stable_path)
        :ok

      {:error, err} ->
        Logger.error("Failed to validate snapshot file! - #{err}")
        {:error, err}
    end
  rescue
    e ->
      Logger.error(
        "Failed to copy snapshot in place, could not read or copy the snapshot file! - #{e}"
      )

      {:error, :enoent}
  end

  @spec get_snapshot_list(Keyword.t()) :: [{String.t(), tuple()}] | no_return()
  def get_snapshot_list(options) do
    options = take_options(options)
    snapshot_path = get_path(:snapshot, options)

    snapshots =
      File.ls!(snapshot_path)
      |> Enum.map(fn id ->
        stat = Path.join(snapshot_path, [id]) |> File.stat!()
        {id, stat.ctime}
      end)
      |> Enum.sort_by(fn {_id, ctime} -> ctime end)

    snapshots
  end

  defp try_restore_tabfile(tabfile_path) do
    Logger.debug("Attempting to load data from file: #{tabfile_path}")

    case PersistFile.decode_file(tabfile_path) do
      {:ok, data} ->
        {:halt, {:ok, :erlang.binary_to_term(data)}}

      {:error, err} ->
        Logger.warning("Failed to load data from file #{tabfile_path} - #{inspect(err)}")
        Logger.warning("Will try another backup file...")
        {:cont, {:error, err}}
    end
  end

  defp take_options(options) when is_list(options) do
    @persist_options
    |> Enum.map(fn {key_name, default_value} ->
      {key_name, Keyword.get(options, key_name, default_value)}
    end)
  end

  defp get_path(:stable, options) do
    dir = Path.join(options[:data_directory], options[:table_name])
    File.mkdir_p!(dir)
    Path.join([options[:data_directory], options[:table_name], @data_stable_name])
  end

  defp get_path(:backup, options) do
    dir = Path.join(options[:data_directory], options[:table_name])
    File.mkdir_p!(dir)
    Path.join([options[:data_directory], options[:table_name], @data_backup_name])
  end

  defp get_path(:snapshot, options) do
    dir = Path.join([options[:data_directory], options[:table_name], "snapshots"])
    File.mkdir_p!(dir)

    dir
  end

  defp get_path(:snapshot, options, snapshot_name) do
    dir = Path.join([options[:data_directory], options[:table_name], "snapshots"])
    File.mkdir_p!(dir)

    Path.join(dir, "#{snapshot_name}")
  end

  defp maybe_clean_old_snapshots(options) do
    snapshot_files = get_snapshot_list(options)

    if length(snapshot_files) > options[:max_snapshots] do
      {to_delete_id, _} = List.first(snapshot_files)

      Logger.warning("Number of snapshots is over configured max: #{options[:max_snapshots]}")
      Logger.warning("Deleting oldest snapshot: #{to_delete_id}")

      to_delete_path = get_path(:snapshot, options, to_delete_id)

      File.rm!(to_delete_path)
    end
  end
end
