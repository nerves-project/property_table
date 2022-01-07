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
  @type metadata :: map()

  @type options :: [name: table_id(), properties: [property_value()]]

  @spec start_link(options()) :: {:ok, pid} | {:error, term}
  def start_link(options) do
    name = Keyword.get(options, :name)

    unless !is_nil(name) and is_atom(name) do
      raise ArgumentError, "expected :name to be given and to be an atom, got: #{inspect(name)}"
    end

    PropertyTable.Supervisor.start_link(options)
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
  @spec subscribe(table_id(), property_with_wildcards()) :: :ok
  def subscribe(table, property) when is_list(property) do
    assert_property_with_wildcards(property)

    registry = PropertyTable.Supervisor.registry_name(table)
    {:ok, _} = Registry.register(registry, :property_registry, property)

    :ok
  end

  @doc """
  Stop subscribing to a property
  """
  @spec unsubscribe(table_id(), property_with_wildcards()) :: :ok
  def unsubscribe(table, property) when is_list(property) do
    registry = PropertyTable.Supervisor.registry_name(table)
    Registry.unregister(registry, :property_registry)
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
  Get a list of all properties matching the specified prefix
  """
  @spec get_by_prefix(table_id(), property()) :: [{property(), value()}]
  def get_by_prefix(table, prefix) when is_list(prefix) do
    assert_property(prefix)

    Table.get_by_prefix(table, prefix)
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
  @spec put(table_id(), property(), value(), metadata()) :: :ok
  def put(table, property, value, metadata \\ %{}) when is_list(property) do
    Table.put(table, property, value, metadata)
  end

  # @doc delegate_to:
  defdelegate clear(table, property), to: Table

  @doc """
  Clear out all properties under a prefix
  """
  defdelegate clear_prefix(table, property), to: Table

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
