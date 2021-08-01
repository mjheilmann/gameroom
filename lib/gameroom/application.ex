defmodule Gameroom.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      GameroomWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Gameroom.PubSub},
      # Start the Endpoint (http/https)
      GameroomWeb.Endpoint,
      # Start a worker by calling: Gameroom.Worker.start_link(arg)
      # {Gameroom.Worker, arg}
      GameroomWeb.Presence
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gameroom.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    GameroomWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
