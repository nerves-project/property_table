defmodule PropertyTable.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: PropertyTable.Worker.start_link(arg)
      # {PropertyTable.Worker, arg}
    ]

    opts = [strategy: :one_for_one, name: PropertyTable.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
