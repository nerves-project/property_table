defmodule PropertyTable do
  @moduledoc File.read!("README.md")
             |> String.split("<!-- MODULEDOC -->")
             |> Enum.fetch!(1)

  alias PropertyTable.Table

  @typedoc """
  A table_id identifies a group of properties
  """
  @type table_id() :: atom()

  @typedoc """
  Properties
  """
  @type property() :: any()
  @type pattern() :: any()
  @type value() :: any()
  @type property_value() :: {property(), value()}

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
  * `:matcher` - set the format for how properties and how they should be
    matched for triggering events. See `PropertyTable.Matcher`.
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

    tuple_events = Keyword.get(options, :tuple_events, false)

    unless is_boolean(tuple_events) do
      raise ArgumentError, "expected :tuple_events to be boolean, got: #{inspect(tuple_events)}"
    end

    matcher = Keyword.get(options, :matcher, PropertyTable.Matcher.StringPath)

    unless is_atom(matcher) do
      raise ArgumentError, "expected :matcher to be module, got: #{inspect(matcher)}"
    end

    properties = Keyword.get(options, :properties, [])

    unless Enum.all?(properties, fn {k, _} -> matcher.check_property(k) == :ok end) do
      raise ArgumentError,
            "expected :properties to contain valid properties, got: #{inspect(properties)}"
    end

    Supervisor.start_link(
      __MODULE__.Supervisor,
      %{table: name, properties: properties, tuple_events: tuple_events, matcher: matcher},
      name: name
    )
  end

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
  @spec subscribe(table_id(), pattern()) :: :ok
  def subscribe(table, pattern) do
    registry = PropertyTable.Supervisor.registry_name(table)
    {:ok, matcher} = Registry.meta(registry, :matcher)

    case matcher.check_pattern(pattern) do
      :ok ->
        {:ok, _} = Registry.register(registry, :subscriptions, pattern)
        :ok

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Stop subscribing to a property
  """
  @spec unsubscribe(table_id(), pattern()) :: :ok
  def unsubscribe(table, pattern) do
    registry = PropertyTable.Supervisor.registry_name(table)
    Registry.unregister_match(registry, :subscriptions, pattern)
  end

  @doc """
  Get the current value of a property
  """
  @spec get(table_id(), property(), value()) :: value()
  def get(table, property, default \\ nil) do
    Table.get(table, property, default)
  end

  @doc """
  Fetch a property with the time that it was set

  Timestamps come from `System.monotonic_time()`
  """
  @spec fetch_with_timestamp(table_id(), property()) :: {:ok, value(), integer()} | :error
  defdelegate fetch_with_timestamp(table, property), to: Table

  @doc """
  Get all properties

  This function might return a really long list so it's mainly intended for
  debug or convenience when you know that the table only contains a few
  properties.
  """
  @spec get_all(table_id()) :: [{property(), value()}]
  defdelegate get_all(table), to: Table

  @doc """
  Get a list of all properties matching the specified property pattern
  """
  @spec match(table_id(), pattern()) :: [{property(), value()}]
  defdelegate match(table, pattern), to: Table

  @doc """
  Update a property and notify listeners
  """
  @spec put(table_id(), property(), value()) :: :ok
  defdelegate put(table, property, value), to: Table

  @doc """
  Delete the specified property
  """
  @spec clear(table_id(), property()) :: :ok
  defdelegate clear(table, property), to: Table

  @doc """
  Clear out all properties that match a pattern
  """
  @spec clear_all(table_id(), pattern()) :: :ok
  defdelegate clear_all(table, pattern), to: Table
end
