defmodule PropertyTable.Supervisor do
  @moduledoc false
  use Supervisor

  @impl Supervisor
  def init(options) do
    registry_name = registry_name(options.table)
    start_time = System.monotonic_time()

    table_options = %{
      matcher: options.matcher,
      registry: registry_name,
      table: options.table,
      event_transformer: options.event_transformer,
      persistence_options: options.persistence_options,
      start_time: start_time
    }

    # Try and restore from disk if persistence options are provided
    # otherwise just create a new ETS table
    if options.persistence_options != nil do
      PropertyTable.Updater.maybe_restore_ets_table(
        options.table,
        options.properties,
        options.persistence_options,
        start_time
      )
    else
      PropertyTable.Updater.create_ets_table(options.table, options.properties, start_time)
    end

    children = [
      {Registry, [keys: :duplicate, name: registry_name, partitions: 1]},
      {PropertyTable.Updater, table_options}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @spec registry_name(PropertyTable.table_id()) :: Registry.registry()
  def registry_name(name) do
    Module.concat(name, Subscriptions)
  end
end
