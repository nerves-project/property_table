defmodule PropertyTable do
  @moduledoc File.read!("README.md")
             |> String.split("## Usage")
             |> Enum.fetch!(1)

  alias PropertyTable.{NoTableError, Table}

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

  @doc false
  defmacro catch_table(table, do: block) do
    quote do
      validate_table!(unquote(table))

      try do
        unquote(block)
      rescue
        e ->
          if Exception.message(e) =~ ~r/does not refer to an existing ETS table|unknown registry/ do
            raise NoTableError, unquote(table)
          else
            raise e
          end
      catch
        :exit, {:noproc, {GenServer, _, _}} ->
          raise NoTableError, unquote(table)
      end
    end
  end

  @doc """
  Subscribe to receive events
  """
  @spec subscribe(table_id(), property_with_wildcards()) :: :ok
  def subscribe(table, property) do
    formatted = format_property!(property, wildcards: true)

    catch_table(table) do
      registry = PropertyTable.Supervisor.registry_name(table)
      {:ok, _} = Registry.register(registry, :property_registry, formatted)

      :ok
    end
  end

  @doc """
  Stop subscribing to a property
  """
  @spec unsubscribe(table_id(), property_with_wildcards()) :: :ok
  def unsubscribe(table, _property) do
    # TODO: Fix unsusbscribing to just a property
    catch_table(table) do
      registry = PropertyTable.Supervisor.registry_name(table)
      Registry.unregister(registry, :property_registry)
      :ok
    end
  end

  @doc """
  Get the current value of a property
  """
  @spec get(table_id(), property(), value()) :: value()
  def get(table, property, default \\ nil) do
    formatted = format_property!(property)
    catch_table(table, do: Table.get(table, formatted, default))
  end

  @doc """
  Fetch a property with the time that it was set

  Timestamps come from `System.monotonic_time()`
  """
  @spec fetch_with_timestamp(table_id(), property()) :: {:ok, value(), integer()} | :error
  def fetch_with_timestamp(table, property) do
    formatted = format_property!(property)
    catch_table(table, do: Table.fetch_with_timestamp(table, formatted))
  end

  @doc """
  Get a list of all properties matching the specified prefix
  """
  @spec get_by_prefix(table_id(), property()) :: [{property(), value()}]
  def get_by_prefix(table, property_prefix) do
    formatted = format_property!(property_prefix)
    catch_table(table, do: Table.get_by_prefix(table, formatted))
  end

  @doc """
  Get a list of all properties matching the specified property pattern
  """
  @spec match(table_id(), property_with_wildcards()) :: [{property(), value()}]
  def match(table, property_pattern) do
    formatted = format_property!(property_pattern, wildcards: true)
    catch_table(table, do: Table.match(table, formatted))
  end

  @doc """
  Update a property and notify listeners
  """
  @spec put(table_id(), property(), value(), metadata()) :: :ok
  def put(table, property, value, metadata \\ %{}) do
    formatted = format_property!(property)
    catch_table(table, do: Table.put(table, formatted, value, metadata))
  end

  @doc """
  Clear a property

  If the property changed, this will send events to all listeners.
  """
  @spec clear(table_id(), property()) :: :ok
  def clear(table, property) do
    formatted = format_property!(property)
    catch_table(table, do: Table.clear(table, formatted))
  end

  @doc """
  Clear out all properties under a prefix
  """
  @spec clear_prefix(table_id(), property()) :: :ok
  def clear_prefix(table, property_prefix) do
    formatted = format_property!(property_prefix)
    catch_table(table, do: Table.clear_prefix(table, formatted))
  end

  defp format_property!(property, opts \\ [])

  defp format_property!(property, opts) when is_binary(property) do
    format_property!(String.split(property, "/", trim: true), opts)
  end

  defp format_property!(property, opts) when is_list(property) do
    allow_wildcards? = opts[:wildcards] == true
    do_format_property(property, [], allow_wildcards?)
  end

  defp format_property!(property, _opts) do
    msg = """
    #{inspect(property)} is not a valid property.

    A property is a hierarchical path represented as a list of strings (["a", "b", "c"])
    or a single string path delimited by `/` ("a/b/c")
    """

    raise ArgumentError, msg
  end

  defp do_format_property([], acc, _), do: Enum.reverse(acc)

  defp do_format_property([next | rest], acc, allow_wildcards?) when next in ["*", :_] do
    if allow_wildcards? do
      do_format_property(rest, [:_ | acc], allow_wildcards?)
    else
      raise ArgumentError,
            "property wildcards can only be used with PropertyTable.subscribe/2 and PropertyTable.match/2"
    end
  end

  defp do_format_property([next | rest], acc, allow_wildcards?) when is_binary(next) do
    do_format_property(rest, [next | acc], allow_wildcards?)
  end

  defp do_format_property([bad | _rest], _acc, _) do
    raise ArgumentError, "#{inspect(bad)} is not a string and cannot be used in a property key"
  end

  defp validate_table!(table) when is_atom(table) and not is_nil(table) do
    :ok
  end

  defp validate_table!(table), do: raise ArgumentError, "#{inspect(table)} is not a valid table id"
end
