defmodule PropertyTable.Table do
  @moduledoc false
  use GenServer

  @doc """
  Create the ETS table that holds all of the properties

  This is done outside of the Table GenServer so that the Table GenServer can
  crash and recover without losing state.
  """
  @spec create_ets_table(PropertyTable.table_id(), [PropertyTable.property_value()]) :: :ok
  def create_ets_table(table, initial_properties) do
    ^table = :ets.new(table, [:named_table, :public, read_concurrency: true])

    # Insert the initial properties
    timestamp = System.monotonic_time()

    Enum.each(initial_properties, fn {property, value} ->
      :ets.insert(table, {property, value, timestamp})
    end)
  end

  @spec start_link({PropertyTable.table_id(), Registry.registry()}) :: GenServer.on_start()
  def start_link({table, _registry_name} = args) do
    GenServer.start_link(__MODULE__, args, name: table)
  end

  @spec get(PropertyTable.table_id(), PropertyTable.property(), PropertyTable.value()) ::
          PropertyTable.value()
  def get(table, property, default) do
    case :ets.lookup(table, property) do
      [{^property, value, _timestamp}] -> value
      [] -> default
    end
  end

  @spec fetch_with_timestamp(PropertyTable.table_id(), PropertyTable.property()) ::
          {:ok, PropertyTable.value(), integer()} | :error
  def fetch_with_timestamp(table, property) do
    case :ets.lookup(table, property) do
      [{^property, value, timestamp}] -> {:ok, value, timestamp}
      [] -> :error
    end
  end

  @spec get_all(PropertyTable.table_id(), PropertyTable.property()) :: [
          {PropertyTable.property(), PropertyTable.value()}
        ]
  def get_all(table, prefix) do
    matchspec = {append(prefix), :"$2", :_}

    :ets.match(table, matchspec)
    |> Enum.map(fn [k, v] -> {prefix ++ k, v} end)
    |> Enum.sort()
  end

  @spec match(PropertyTable.table_id(), PropertyTable.property_with_wildcards()) :: [
          {PropertyTable.property(), PropertyTable.value()}
        ]
  def match(table, pattern) do
    :ets.match(table, {:"$1", :"$2", :_})
    |> Enum.filter(fn [k, _v] ->
      is_property_match?(pattern, k)
    end)
    |> Enum.map(fn [k, v] -> {k, v} end)
    |> Enum.sort()
  end

  @dialyzer {:nowarn_function, append: 1}
  defp append([]), do: :"$1"
  defp append([h]), do: [h | :"$1"]
  defp append([h | t]), do: [h | append(t)]

  @doc """
  Update or add a property

  If the property changed, this will send events to all listeners.
  """
  @spec put(
          PropertyTable.table_id(),
          PropertyTable.property(),
          PropertyTable.value(),
          PropertyTable.metadata()
        ) ::
          :ok

  def put(table, property, nil, _metadata) do
    clear(table, property)
  end

  def put(table, property, value, metadata) do
    GenServer.call(table, {:put, property, value, System.monotonic_time(), metadata})
  end

  @doc """
  Clear a property

  If the property changed, this will send events to all listeners.
  """
  @spec clear(PropertyTable.table_id(), PropertyTable.property()) :: :ok
  def clear(table, property) when is_list(property) do
    GenServer.call(table, {:clear, property})
  end

  @doc """
  Clear out all of the properties under a prefix
  """
  @spec clear_prefix(PropertyTable.table_id(), PropertyTable.property()) :: :ok
  def clear_prefix(table, property) when is_list(property) do
    GenServer.call(table, {:clear_prefix, property})
  end

  @impl GenServer
  def init({table, registry_name}) do
    {:ok, %{table: table, registry: registry_name}}
  end

  @impl GenServer
  def handle_call({:put, property, value, timestamp, metadata}, _from, state) do
    case :ets.lookup(state.table, property) do
      [{^property, ^value, _last_change}] ->
        # No change, so no notifications
        :ok

      [{^property, old_value, last_change}] ->
        timestamp_metadata = %{
          old_timestamp: last_change,
          new_timestamp: timestamp
        }

        updated_metadata = Map.merge(timestamp_metadata, metadata)

        :ets.insert(state.table, {property, value, timestamp})
        dispatch(state, property, old_value, value, updated_metadata)

      [] ->
        :ets.insert(state.table, {property, value, timestamp})
        dispatch(state, property, nil, value, metadata)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:clear, property}, _from, state) do
    case :ets.lookup(state.table, property) do
      [{^property, old_value, _timestamp}] ->
        :ets.delete(state.table, property)
        dispatch(state, property, old_value, nil, %{})

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:clear_prefix, prefix}, _from, state) do
    to_delete = get_all(state.table, prefix)
    metadata = %{}

    # Delete everything first and then send notifications so
    # if handlers call "get", they won't see something that
    # will be deleted shortly.
    Enum.each(to_delete, fn {property, _value} ->
      :ets.delete(state.table, property)
    end)

    Enum.each(to_delete, fn {property, value} ->
      dispatch(state, property, value, nil, metadata)
    end)

    {:reply, :ok, state}
  end

  defp dispatch(state, property, old_value, new_value, metadata) do
    message = {state.table, property, old_value, new_value, metadata}

    Registry.match(state.registry, :property_registry, :_)
    |> Enum.each(fn {pid, match} ->
      is_property_prefix_match?(match, property) && send(pid, message)
    end)
  end

  # Check if the first parameter is a prefix of the second parameter with
  # wildcards
  defp is_property_prefix_match?([], _property), do: true

  defp is_property_prefix_match?([value | match_rest], [value | property_rest]) do
    is_property_prefix_match?(match_rest, property_rest)
  end

  defp is_property_prefix_match?([:_ | match_rest], [_any | property_rest]) do
    is_property_prefix_match?(match_rest, property_rest)
  end

  defp is_property_prefix_match?(_match, _property), do: false

  # Check if the first parameter matches the second parameter with wildcards
  defp is_property_match?([], []), do: true

  defp is_property_match?([value | match_rest], [value | property_rest]) do
    is_property_match?(match_rest, property_rest)
  end

  defp is_property_match?([:_ | match_rest], [_any | property_rest]) do
    is_property_match?(match_rest, property_rest)
  end

  defp is_property_match?(_match, _property), do: false
end
