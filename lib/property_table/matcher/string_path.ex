# SPDX-FileCopyrightText: 2022 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule PropertyTable.Matcher.StringPath do
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

  @behaviour PropertyTable.Matcher

  @doc """
  Check whether a property is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @impl PropertyTable.Matcher
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
  @impl PropertyTable.Matcher
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
  @impl PropertyTable.Matcher
  def matches?([value | match_rest], [value | property_rest]) do
    __MODULE__.matches?(match_rest, property_rest)
  end

  def matches?([:_ | match_rest], [_any | property_rest]) do
    __MODULE__.matches?(match_rest, property_rest)
  end

  def matches?([], _property), do: true
  def matches?([:"$"], []), do: true
  def matches?(_pattern, _property), do: false

  @doc """
  Build an ETS match-spec equivalent to `matches?/2` for `pattern`

  StringPath patterns translate directly into list patterns in the match-spec
  head: `:_` is already an ETS wildcard, and the tail is left open with `:_`
  unless the pattern ends in `:"$"`, in which case it is `[]` to anchor the
  length. The body returns the whole row via `:"$_"`, so PropertyTable does
  not need to know the row layout. Returns `:error` for invalid patterns.
  """
  @impl PropertyTable.Matcher
  def match_spec(pattern) do
    case check_pattern(pattern) do
      :ok -> [{{property_pattern(pattern), :_, :_}, [], [:"$_"]}]
      {:error, _} -> :error
    end
  end

  defp property_pattern([]), do: :_
  defp property_pattern([:"$"]), do: []
  defp property_pattern([seg | rest]), do: [seg | property_pattern(rest)]
end
