defmodule PropertyTable.Supervisor do
  @moduledoc false
  use Supervisor

  @impl Supervisor
  def init(options) do
    registry_name = registry_name(options.table)

    table_options = %{
      matcher: options.matcher,
      registry: registry_name,
      table: options.table,
      tuple_events: options.tuple_events
    }

    PropertyTable.Updater.create_ets_table(options.table, options.properties)

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
