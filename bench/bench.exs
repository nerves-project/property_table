# SPDX-FileCopyrightText: 2022 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule NonMatchingSub do
  use GenServer

  def init(_) do
    PropertyTable.subscribe(BencheeTable, ["non_matching", :_])
    {:ok, :no_state}
  end
end

create_properties = fn values -> for v <- values, do: {["first", "#{v}"], v} end

create_sub = fn ->
  {:ok, pid} = GenServer.start(NonMatchingSub, [])
  pid
end

starter_properties = create_properties.(1_000_000..1_000_100)

inputs = [
  {"100 properties/0 subs",
   %{
     initial_properties: starter_properties,
     non_matching_subscribers: 0,
     add: create_properties.(1..100)
   }},
  {"1000 properties/0 subs",
   %{
     initial_properties: starter_properties,
     non_matching_subscribers: 0,
     add: create_properties.(1..1000)
   }},
  {"100 properties/2 subs",
   %{
     initial_properties: starter_properties,
     non_matching_subscribers: 2,
     add: create_properties.(1..100)
   }},
  {"1000 properties/2 subs",
   %{
     initial_properties: starter_properties,
     non_matching_subscribers: 2,
     add: create_properties.(1..1000)
   }}
]

Benchee.run(
  %{
    "insertion" => fn input ->
      Enum.each(input.add, fn {k, v} -> PropertyTable.put(BencheeTable, k, v) end)
      input
    end,
    "get 1000x" => fn input ->
      for _ <- 1..1000, do: PropertyTable.get(BencheeTable, ["first", "1000042"])
      input
    end
  },
  warmup: 1,
  time: 5,
  memory_time: 1,
  inputs: inputs,
  before_each: fn input ->
    {:ok, pid} = PropertyTable.start_link(name: BencheeTable)
    Enum.each(input.initial_properties, fn {k, v} -> PropertyTable.put(BencheeTable, k, v) end)

    for _ <- 1..input.non_matching_subscribers do
      create_sub.()
    end

    Map.put(input, :supervisor, pid)
  end,
  after_each: fn input ->
    Supervisor.stop(input.supervisor)
  end,
  formatters: [Benchee.Formatters.Console]
)
