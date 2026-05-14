# SPDX-FileCopyrightText: 2022 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule PropertyTable.Matcher do
  @moduledoc """
  Behaviour for customizing the Matcher logic for filtering and dispatching events
  """

  @doc """
  Check whether a property is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @callback check_property(PropertyTable.property()) :: :ok | {:error, Exception.t()}

  @doc """
  Check whether a pattern is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @callback check_pattern(PropertyTable.pattern()) :: :ok | {:error, Exception.t()}

  @doc """
  Returns true if the pattern matches the specified property
  """
  @callback matches?(PropertyTable.pattern(), PropertyTable.property()) :: boolean()

  @doc """
  Build an ETS match-spec for `pattern`

  This is an optional callback. When implemented, `PropertyTable.match/2` will
  call it to obtain a match-spec and run the scan with `:ets.select/2`. This can
  be much faster on large tables than iterating over rows calling `matches?/2`.
  Return `:error` to fall back to the generic `matches?/2` path.

  The match-spec must handle `{property, value, meta}` triples. Return
  rows unmodified by specifying `[:"$_"]` in the third tuple element.
  """
  @callback match_spec(PropertyTable.pattern()) ::
              [{tuple(), [term()], [term()]}] | :error

  @optional_callbacks match_spec: 1
end
