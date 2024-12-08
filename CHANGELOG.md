# Changelog

## v0.2.6

* New feature
  * Added `:event_transformer` option that takes a function to transform a
    `PropertyTable.Event.t()` into a custom data structure for subscribers. This
    lets users abstract away the use of `PropertyTable`.

* Fixes
  * The `:previous_timestamp` field in change events had been set to `nil` when
    no information was known about the previous state of the property. It's now
    set to the `PropertyTable`'s start time to fix the typespec violation (`nil`
    wasn't valid) and help differentiate unknown properties due to app restarts
    vs.  not being set.
  * Properties set at initialization, including restored ones, all have the same
    timestamp.

## v0.2.5

* Fix incorrect typespec for `PropertyTable.options()`

## v0.2.4

* Updates
  * Fix unintended exceptions being raised when the filesystem updates start
    failing when table persistence is enabled
  * Reduce time when an unexpected VM exit could result in a corrupt persisted
    file. The backup would be usable, but now the critical steps only involve
    renaming or deleting files.

## v0.2.3

* Updates
  * Fix compiler warnings with Elixir 1.15

## v0.2.2

* Updates
  * Fixed missing `:crypto` dependency warning.

## v0.2.1

* New features
  * Automatic persistence and snapshots for PropertyTables. This makes it
    possible to use `PropertyTable` for small key/value stores like those for
    storing runtime settings especially for Nerves devices. PropertyTable
    protects against corruption and unexpected reboots that happen mid-write.

## v0.2.0

* Backwards incompatible changes
  * `nil` no longer deletes a property from the table. In other words, it's ok to
    for properties to be `nil` now.
  * `PropertyTable.clear/2` and `PropertyTable.clear_all/2` were renamed to
    `PropertyTable.delete/2` and `PropertyTable.delete_matches/2` respectively.
  * `PropertyTable.put/3` raises if you give it an invalid property rather than
    returning an error tuple. Since these are usually programming errors anyway,
    this change removes the need for a return value check for Dialyzer.

* New features
  * Added `PropertyTable.put_many/2`. It's possible to add many properties to
    the table atomically. Change notifications still only get sent for
    properties that really changed.

## v0.1.0

Initial release

This code was extracted from `vintage_net`, simplified and modified to support
more use cases.
