defmodule GameroomWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :gameroom,
    pubsub_server: Gameroom.PubSub

  @doc """
  Merges joins and leaves diff into the current presences map.
  """
  def handle_diff(presences, %{joins: joins, leaves: leaves}) do
    presences
    |> Map.drop(Map.keys(leaves))
    |> Map.merge(joins)
  end
end
