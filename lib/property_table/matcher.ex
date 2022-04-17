defmodule PropertyTable.Matcher do
  @moduledoc """
  Match logic using keys organized as hierarchical lists

  Property keys that are lists look like `["first", "second", "third"]`.
  These are intended to create a hierarchical organization of keys. Matching
  patterns involves checking whether the pattern is at the beginning of the
  key. This makes it possible to get notified on every property change where
  the key begins with `["first", "second"]`. This is a really common use case
  when using hierarchically organized keys.

  Two special atoms can be used:

  * `:_` - match anything at this part of the list
  * `:$` - match the end of the list
  """

  @doc """
  Check whether a property is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @spec check_property(PropertyTable.property()) :: :ok | {:error, Exception.t()}
  def check_property([]), do: :ok

  def check_property([part | rest]) when is_binary(part) do
    check_property(rest)
  end

  def check_property([part | _]) do
    {:error, ArgumentError.exception("Invalid property element '#{inspect(part)}'")}
  end

  def check_property(_other) do
    {:error, ArgumentError.exception("Pattern should be a list of strings")}
  end

  @doc """
  Check whether a pattern is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @spec check_pattern(PropertyTable.pattern()) :: :ok | {:error, Exception.t()}
  def check_pattern([]), do: :ok

  def check_pattern([part | rest]) when is_binary(part) or part in [:_, :"$"] do
    check_pattern(rest)
  end

  def check_pattern([part | _]) do
    {:error, ArgumentError.exception("Invalid pattern element '#{inspect(part)}'")}
  end

  def check_pattern(_other) do
    {:error, ArgumentError.exception("Pattern should be a list of strings or wildcard")}
  end

  @doc """
  Returns true if the pattern matches the specified property
  """
  @spec match?(PropertyTable.pattern(), PropertyTable.property()) :: boolean()
  def match?([], _property), do: true

  def match?([value | match_rest], [value | property_rest]) do
    __MODULE__.match?(match_rest, property_rest)
  end

  def match?([:_ | match_rest], [_any | property_rest]) do
    __MODULE__.match?(match_rest, property_rest)
  end

  def match?([:"$"], []), do: true

  def match?(_match, _property), do: false
end
