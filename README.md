# PropertyTable

In-memory key-value store with subscriptions

## Usage

PropertyTables are in-memory key-value stores

Users can subscribe to keys or groups of keys to be notified of changes.

Keys are hierarchically layed out with each key being represented as a list
of strings for the path to the key and referred to as a "property".
For example, if you wanted to store properties for network interfaces, you
might have a table called `NetworkTable` with a hierarchy like this:

```sh
NetworkTable
├── available_interfaces
│   └── [eth0, eth1]
└── interface
|   ├── eth0
|   │   ├── config
|   |   |   └── %{ipv4: %{method: :dhcp}}
|   │   └── connection
|   |       └── :internet
|   └── eth1
|       ├── config
|       |   └── %{ipv4: %{method: :static}}
|       └── connection
|           └── :disconnected
└── connection
    └── :internet
```

And inserting the values to the table would look like:

```elixir
PropertyTable.put(NetworkTable, ["available_interfaces"], ["eth0", "eth1"])
PropertyTable.put(NetworkTable, ["connection"], :internet)
PropertyTable.put(NetworkTable, ["interface", "eth0", "config"], %{ipv4: %{method: :dhcp}})
```

Values can be any Elixir data structure except for `nil`. `nil` is used to
identify non-existent properties. Therefore, setting a property to `nil` deletes
the property.

Users can get and listen for changes in multiple properties by specifying the beginning of a
path. For example, if you wanted to get every property that begins with `"interface"`, run:

```elixir
PropertyTable.get_all(NetworkTable, ["interface"])
```

Likewise, you can subscribe to changes to receive a message after each change
happens. For example, to receive a message when any property starting with
`"interface"` changes, run:

```elixir
PropertyTable.subscribe(table, ["interface"])
```

Then when a property changes value, the Erlang process that called
`PropertyTable.subscribe/2` will receive a `%PropertyTable.Event{}` message:

```elixir
%PropertyTable.Event{
  table: NetworkTable,
  property: ["interface", "eth0", "config"],
  value: %{ipv4: %{method: :dhcp}}
  timestamp: 200,
  previous_value: %{},
  previous_timestamp: 100
}
```

As shown, events not only contain the property and new value, but also
information about the previous value.

## License

Copyright (C) 2022 Nerves Project Authors

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
