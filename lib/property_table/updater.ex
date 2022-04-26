defmodule PropertyTable.Updater do
  # GenServer that's responsible for updating the ETS table that stores all
  # properties. All writes to the table are routed through here.  Table reads
  # can happen other places.

  @moduledoc false
  use GenServer

  alias PropertyTable.Event

  require Logger

  @type state() :: %{
          table: PropertyTable.table_id(),
          registry: Registry.registry(),
          tuple_events: boolean(),
          matcher: module()
        }

  @doc """
  Create the ETS table that holds all of the properties

  This is done outside of the Updater GenServer so that the Updater GenServer can
  crash and recover without losing state.
  """
  @spec create_ets_table(PropertyTable.table_id(), [PropertyTable.property_value()]) :: :ok
  def create_ets_table(table, initial_properties) do
    ^table = :ets.new(table, [:named_table, :public])

    # Insert the initial properties
    timestamp = System.monotonic_time()

    Enum.each(initial_properties, fn {property, value} ->
      :ets.insert(table, {property, value, timestamp})
    end)
  end

  @doc false
  @spec server_name(PropertyTable.table_id()) :: atom
  def server_name(name) do
    Module.concat(name, Updater)
  end

  @spec start_link(state()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts.table))
  end

  @doc """
  Update or add a property

  If the property changed, this will send events to all listeners.
  """
  @spec put(PropertyTable.table_id(), PropertyTable.property(), PropertyTable.value()) :: :ok
  def put(table, property, value) do
    case GenServer.call(server_name(table), {:put, property, value, System.monotonic_time()}) do
      :ok -> :ok
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update many properties

  This is similar to calling `put/3` several times in a row, but atomically. It is
  also slightly more efficient when updating more than one property.
  """
  @spec put_many(PropertyTable.table_id(), [{PropertyTable.property(), PropertyTable.value()}]) ::
          :ok
  def put_many(table, properties) when is_list(properties) do
    timestamp = System.monotonic_time()

    timestamped_properties = for {property, value} <- properties, do: {property, value, timestamp}

    case GenServer.call(server_name(table), {:put_many, timestamped_properties}) do
      :ok -> :ok
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete a property
  """
  @spec delete(PropertyTable.table_id(), PropertyTable.property()) :: :ok
  def delete(table, property) do
    GenServer.call(server_name(table), {:delete, property, System.monotonic_time()})
  end

  @doc """
  Delete every property that matches the pattern
  """
  @spec delete_matches(PropertyTable.table_id(), PropertyTable.pattern()) :: :ok
  def delete_matches(table, pattern) do
    GenServer.call(server_name(table), {:delete_matches, pattern, System.monotonic_time()})
  end

  @impl GenServer
  def init(opts) do
    Registry.put_meta(opts.registry, :matcher, opts.matcher)

    {:ok, opts}
  end

  @impl GenServer
  def handle_call({:put, property, value, timestamp}, _from, state) do
    result =
      with :ok <- state.matcher.check_property(property) do
        case :ets.lookup(state.table, property) do
          [{_property, ^value, _last_change}] ->
            # No change, so no notifications
            :ok

          [{_property, previous_value, last_change}] ->
            event = %Event{
              table: state.table,
              property: property,
              value: value,
              previous_value: previous_value,
              timestamp: timestamp,
              previous_timestamp: last_change
            }

            :ets.insert(state.table, {property, value, timestamp})
            dispatch(state, event)

          [] ->
            :ets.insert(state.table, {property, value, timestamp})

            event = %Event{
              table: state.table,
              property: property,
              value: value,
              previous_value: nil,
              timestamp: timestamp,
              previous_timestamp: nil
            }

            dispatch(state, event)
        end
      end

    {:reply, result, state}
  end

  def handle_call({:put_many, timestamped_properties}, _from, state) do
    unique_props = trim_duplicate_puts(timestamped_properties)

    result =
      with :ok <- check_properties(unique_props, state.matcher) do
        {props, events} = compute_events(unique_props, state, {[], []})
        :ets.insert(state.table, props)
        Enum.each(events, &dispatch(state, &1))
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, property, timestamp}, _from, state) do
    case :ets.take(state.table, property) do
      [{_property, previous_value, last_change}] ->
        event = %Event{
          table: state.table,
          property: property,
          value: nil,
          previous_value: previous_value,
          timestamp: timestamp,
          previous_timestamp: last_change
        }

        dispatch(state, event)

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_matches, pattern, timestamp}, _from, state) do
    to_delete = match_with_timestamp(state.table, state.matcher, pattern)

    # Delete everything first and then send notifications so
    # if handlers call "get", they won't see something that
    # will be deleted shortly.
    Enum.each(to_delete, fn {property, _value, _timestamp} ->
      :ets.delete(state.table, property)
    end)

    Enum.each(to_delete, fn {property, previous_value, previous_timestamp} ->
      event = %Event{
        table: state.table,
        property: property,
        value: nil,
        previous_value: previous_value,
        timestamp: timestamp,
        previous_timestamp: previous_timestamp
      }

      dispatch(state, event)
    end)

    {:reply, :ok, state}
  end

  defp match_with_timestamp(table, matcher, pattern) do
    :ets.foldl(
      fn {property, value, timestamp}, acc ->
        if matcher.matches?(pattern, property) do
          [{property, value, timestamp} | acc]
        else
          acc
        end
      end,
      [],
      table
    )
  end

  defp dispatch(state, event) do
    message = if state.tuple_events, do: Event.to_tuple(event), else: event
    matcher = state.matcher
    property = event.property

    Registry.dispatch(state.registry, :subscriptions, fn entries ->
      for {pid, pattern} <- entries,
          matcher.matches?(pattern, property),
          do: send(pid, message)
    end)
  end

  defp trim_duplicate_puts(properties) do
    # Keep the last value - no transients
    properties
    |> Enum.reverse()
    |> Enum.uniq_by(fn {property, _, _} -> property end)
  end

  defp check_properties([{property, _, _} | rest], matcher) do
    case matcher.check_property(property) do
      :ok -> check_properties(rest, matcher)
      result -> result
    end
  end

  defp check_properties([], _matcher), do: :ok

  defp check_properties([other | _], _matcher) do
    {:error, ArgumentError.exception("Expected list of tuples. Got #{inspect(other)}")}
  end

  defp compute_events([{property, value, timestamp} = prop | rest], state, {props, events} = acc) do
    new_acc =
      case :ets.lookup(state.table, property) do
        [{_property, ^value, _last_change}] ->
          # No change; no notifications
          acc

        [{_property, previous_value, last_change}] ->
          {[prop | props],
           [
             %Event{
               table: state.table,
               property: property,
               value: value,
               previous_value: previous_value,
               timestamp: timestamp,
               previous_timestamp: last_change
             }
             | events
           ]}

        [] ->
          {[prop | props],
           [
             %Event{
               table: state.table,
               property: property,
               value: value,
               previous_value: nil,
               timestamp: timestamp,
               previous_timestamp: nil
             }
             | events
           ]}
      end

    compute_events(rest, state, new_acc)
  end

  defp compute_events([], _state, acc), do: acc
end
