defmodule PropertyTable do
  @moduledoc File.read!("README.md")
             |> String.split("## Usage")
             |> Enum.fetch!(1)

  alias PropertyTable.Table

  @typedoc """
  A table_id identifies a group of properties
  """
  @type table_id() :: atom()

  @typedoc """
  Properties
  """
  @type property :: [String.t()]
  @type property_with_wildcards :: [String.t() | :_]
  @type value :: any()
  @type property_value :: {property(), value()}

  @typedoc """
  PropertyTable configuration options

  See `start_link/2` for usage.
  """
  @type option() ::
          {:name, table_id()} | {:properties, [property_value()]} | {:tuple_events, boolean()}

  @doc """
  Start a PropertyTable's supervision tree

  To create a PropertyTable for your application or library, add the following
  `child_spec` to one of your supervision trees:

  ```elixir
  {PropertyTable, name: MyTableName}
  ```

  The `:name` option is required. All calls to `PropertyTable` will need to
  know it and the process will be registered under than name so be sure it's
  unique.

  Additional options are:

  * `:properties` - a list of `{property, value}` tuples to initially populate
    the `PropertyTable`
  * `:tuple_events` - set to `true` for change events to be in the old tuple
    format. This is not recommended for new code and hopefully will be removed
    in the future.
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(options) do
    name =
      case Keyword.fetch(options, :name) do
        {:ok, name} when is_atom(name) ->
          name

        {:ok, other} ->
          raise ArgumentError, "expected :name to be an atom, got: #{inspect(other)}"

        :error ->
          raise ArgumentError, "expected :name option to be present"
      end

    properties = Keyword.get(options, :properties, [])

    unless Enum.all?(properties, &property_tuple?/1) do
      raise ArgumentError,
            "expected :properties to be a list of property/value tuples, got: #{inspect(properties)}"
    end

    tuple_events = Keyword.get(options, :tuple_events, false)

    unless is_boolean(tuple_events) do
      raise ArgumentError, "expected :tuple_events to be boolean, got: #{inspect(tuple_events)}"
    end

    Supervisor.start_link(
      __MODULE__.Supervisor,
      %{table: name, properties: properties, tuple_events: tuple_events},
      name: name
    )
  end

  defp property_tuple?({property, _value}) when is_list(property), do: true
  defp property_tuple?(_), do: false

  @doc """
  Returns a specification to start a property_table under a supervisor.
  See `Supervisor`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, PropertyTable),
      start: {PropertyTable, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Subscribe to receive events
  """
  @spec subscribe(table_id(), property_with_wildcards()) :: :ok
  def subscribe(table, property) when is_list(property) do
    assert_property_with_wildcards(property)

    registry = PropertyTable.Supervisor.registry_name(table)
    {:ok, _} = Registry.register(registry, :subscriptions, property)

    :ok
  end

  @doc """
  Stop subscribing to a property
  """
  @spec unsubscribe(table_id(), property_with_wildcards()) :: :ok
  def unsubscribe(table, property) when is_list(property) do
    registry = PropertyTable.Supervisor.registry_name(table)
    Registry.unregister(registry, :subscriptions)
  end

  @doc """
  Get the current value of a property
  """
  @spec get(table_id(), property(), value()) :: value()
  def get(table, property, default \\ nil) when is_list(property) do
    assert_property(property)
    Table.get(table, property, default)
  end

  @doc """
  Fetch a property with the time that it was set

  Timestamps come from `System.monotonic_time()`
  """
  @spec fetch_with_timestamp(table_id(), property()) :: {:ok, value(), integer()} | :error
  def fetch_with_timestamp(table, property) when is_list(property) do
    assert_property(property)
    Table.fetch_with_timestamp(table, property)
  end

  @doc """
  Get all properties

  It's possible to pass a prefix to only return properties under a specific path.
  """
  @spec get_all(table_id(), property()) :: [{property(), value()}]
  def get_all(table, prefix \\ []) when is_list(prefix) do
    assert_property(prefix)

    Table.get_all(table, prefix)
  end

  @doc """
  Get a list of all properties matching the specified property pattern
  """
  @spec match(table_id(), property_with_wildcards()) :: [{property(), value()}]
  def match(table, pattern) when is_list(pattern) do
    assert_property_with_wildcards(pattern)

    Table.match(table, pattern)
  end

  @doc """
  Update a property and notify listeners
  """
  @spec put(table_id(), property(), value()) :: :ok
  def put(table, property, value) when is_list(property) do
    Table.put(table, property, value)
  end

  @doc """
  Delete the specified property
  """
  @spec clear(table_id(), property()) :: :ok
  defdelegate clear(table, property), to: Table

  @doc """
  Clear out all properties under a prefix
  """
  @spec clear_all(table_id(), property()) :: :ok
  defdelegate clear_all(table, property), to: Table

  defp assert_property(property) do
    Enum.each(property, fn
      v when is_binary(v) -> :ok
      :_ -> raise ArgumentError, "Wildcards not allowed in this property"
      _ -> raise ArgumentError, "Property should be a list of strings"
    end)
  end

  defp assert_property_with_wildcards(property) do
    Enum.each(property, fn
      v when is_binary(v) -> :ok
      :_ -> :ok
      _ -> raise ArgumentError, "Property should be a list of strings"
    end)
  end
end
