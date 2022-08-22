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

  # Options for persisting to disk, and their default values
  @persist_options %{
    data_directory: "/data/property_table",
    table_name: nil,
    max_snapshots: 25
  }

  @data_stable_name "prop_table.db"
  @data_backup_name "prop_table.db.backup"

  @spec persist_to_disk(reference() | atom(), Keyword.t()) :: :ok | :error | no_return()
  def persist_to_disk(table, options) do
    options = take_options(options)

    stable_path = get_path(:stable, options)
    backup_path = get_path(:backup, options)

    if File.exists?(stable_path) do
      # Move the current stable data file to the backup path
      Logger.debug("Moving stable data file to backup: #{stable_path} => #{backup_path}")
      File.rename!(stable_path, backup_path)

      Logger.debug("Writing PropertyTable to #{stable_path}")
      :ok = :ets.tab2file(table, stable_path |> to_charlist(), extended_info: [:md5sum])
    else
      Logger.debug("Writing PropertyTable to #{stable_path}")
      :ok = :ets.tab2file(table, stable_path |> to_charlist(), extended_info: [:md5sum])
    end

    :ok
  rescue
    e ->
      Logger.error("Failed to persist table to disk: #{e}")
      :error
  end

  @spec restore_from_disk(Keyword.t()) :: {:ok, reference() | atom()} | {:error, atom()}
  def restore_from_disk(options) do
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
          Logger.warn("File #{path} does not exist! Trying a backup file...")
          {:cont, {:error, :enoent}}
        end
      end)

    case result do
      {:ok, table} ->
        {:ok, table}

      {:error, _} ->
        Logger.error(
          "DATA LOSS! - We could not load the stable file, or the backup file! If you have snapshots consider restoring from those!"
        )

        {:error, :failed_to_restore}
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

    snapshot_id =
      :ets.tab2list(table)
      |> :erlang.phash2()
      |> to_string()

    timestamp = DateTime.utc_now() |> to_string()
    full_snapshot_name = "#{timestamp}_#{snapshot_id}"
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

  @spec restore_snapshot(Keyword.t(), String.t()) :: :ok | {:error, :enoent} | no_return()
  def restore_snapshot(options, snapshot_id) do
    options = take_options(options)
    stable_path = get_path(:stable, options)
    snapshots_path = get_path(:snapshot, options) |> Path.join("*_#{snapshot_id}")
    found_snapshot = Path.wildcard(snapshots_path)

    if length(found_snapshot) != 1 do
      {:error, :enoent}
    else
      [to_restore] = found_snapshot

      # Copy the found snapshot in place of the current stable db path
      Logger.debug("Restoring table file snapshot: #{to_restore} => #{stable_path}")
      File.copy!(to_restore, stable_path)

      :ok
    end
  end

  @spec get_snapshot_list(Keyword.t()) :: [{String.t(), String.t()}] | no_return()
  def get_snapshot_list(options) do
    options = take_options(options)
    snapshot_path = get_path(:snapshot, options, "*")

    Path.wildcard(snapshot_path)
    |> Enum.sort()
    |> Enum.map(fn file_path ->
      snapshot_id = String.split(file_path, "_") |> List.last()
      full_name = Path.basename(file_path)
      {snapshot_id, full_name}
    end)
  end

  defp try_restore_tabfile(tabfile_path) do
    Logger.debug("Attempting to restore from file: #{tabfile_path}")

    converted_path = to_charlist(tabfile_path)

    case :ets.file2tab(converted_path, verify: true) do
      {:ok, table} ->
        {:halt, {:ok, table}}

      {:error, err} ->
        Logger.warn("Failed to restore from file #{tabfile_path} - #{inspect(err)}")
        Logger.warn("Will try another backup file...")
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
    Path.join(options[:data_directory], [options[:table_name], "/", @data_stable_name])
  end

  defp get_path(:backup, options) do
    dir = Path.join(options[:data_directory], options[:table_name])
    File.mkdir_p!(dir)
    Path.join(options[:data_directory], [options[:table_name], "/", @data_backup_name])
  end

  defp get_path(:snapshot, options) do
    dir = Path.join(options[:data_directory], [options[:table_name], "/", "snapshots"])
    File.mkdir_p!(dir)

    dir
  end

  defp get_path(:snapshot, options, snapshot_name) do
    dir = Path.join(options[:data_directory], [options[:table_name], "/", "snapshots"])
    File.mkdir_p!(dir)

    Path.join(dir, "snapshot_#{snapshot_name}")
  end

  defp maybe_clean_old_snapshots(options) do
    snapshot_path = get_path(:snapshot, options, "*")
    snapshot_files = Path.wildcard(snapshot_path) |> Enum.sort()

    if length(snapshot_files) > options[:max_snapshots] do
      to_delete = List.first(snapshot_files)
      Logger.warn("Number of snapshots is over configured max: #{options[:max_snapshots]}")
      Logger.warn("Deleting oldest snapshot: #{to_delete}")

      File.rm!(to_delete)
    end
  end
end
