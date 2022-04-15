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

inputs = [
  {"100 properties/0 subs",
   %{initial_properties: [], non_matching_subscribers: 0, add: create_properties.(1..100)}},
  {"1000 properties/0 subs",
   %{initial_properties: [], non_matching_subscribers: 0, add: create_properties.(1..1000)}},
  {"100 properties/2 subs",
   %{initial_properties: [], non_matching_subscribers: 2, add: create_properties.(1..100)}},
  {"1000 properties/2 subs",
   %{initial_properties: [], non_matching_subscribers: 2, add: create_properties.(1..1000)}}
]

Benchee.run(
  %{
    "insertion" => fn input ->
      Enum.each(input.add, fn {k, v} -> PropertyTable.put(BencheeTable, k, v) end)
      input
    end
  },
  warmup: 2,
  time: 10,
  memory_time: 1,
  inputs: inputs,
  before_each: fn input ->
    {:ok, pid} = PropertyTable.Supervisor.start_link(name: BencheeTable)
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
