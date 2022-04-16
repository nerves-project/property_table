defmodule PropertyTable.Supervisor do
  @moduledoc """
  Supervisor for using a PropertyTable

  To create a PropertyTable for your application or library, add the following
  `child_spec` to one of your supervision trees:

  ```elixir
  {PropertyTable.Supervisor, name: MyTableName}
  ```

  The `:name` option is required. All calls to `PropertyTable` will need to
  know it. Other options are:

  * `:properties` - a list of `{property, value}` tuples to initially populate
  the `PropertyTable`
  """
  use Supervisor

  @doc """
  Manually start a PropertyTable Supervisor

  Normally you should add a `child_spec` to your supervision tree to create a
  new `PropertyTable`.
  """
  @spec start_link([PropertyTable.option()]) :: Supervisor.on_start()
  def start_link(options) do
    name = Keyword.get(options, :name)

    unless !is_nil(name) and is_atom(name) do
      raise ArgumentError, "expected :name to be given and to be an atom, got: #{inspect(name)}"
    end

    Supervisor.start_link(__MODULE__, options)
  end

  @impl Supervisor
  def init(options) do
    name = Keyword.fetch!(options, :name)
    properties = Keyword.get(options, :properties, [])
    registry_name = registry_name(name)
    updated_options = Keyword.put(options, :registry_name, registry_name)

    PropertyTable.Table.create_ets_table(name, properties)

    children = [
      {PropertyTable.Table, updated_options},
      {Registry, [keys: :duplicate, name: registry_name]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  @spec registry_name(PropertyTable.table_id()) :: Registry.registry()
  def registry_name(name) do
    Module.concat(PropertyTable.Registry, name)
  end
end
