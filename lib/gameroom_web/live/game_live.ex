defmodule GameroomWeb.GameLive do
  @moduledoc """
  LiveView for multiplayer game rooms.
  """
  use GameroomWeb, :live_view

  alias Gameroom.Games

  @impl true
  def mount(%{"room_id" => room_id}, session, socket) do
    player_id = session["player_id"] || Ecto.UUID.generate()
    player_name = session["player_name"] || Games.generate_player_name()

    room_exists? = Games.room_exists?(room_id)

    {:ok,
     socket
     |> assign(
       room_id: room_id,
       room_exists?: room_exists?,
       player_id: player_id,
       player_name: player_name,
       page_title: "Room #{room_id} · GameRoom"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="game-room-container" class="space-y-6">
        <div class="flex items-center justify-between pb-4 border-b border-base-200">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="size-4 mr-1" /> Back to Lobby
            </.link>
            <h1 class="text-xl font-bold font-mono">{@room_id}</h1>
          </div>
        </div>

        <%= if @room_exists? do %>
          <div class="card bg-base-200/50 p-8 text-center rounded-2xl border border-base-300">
            <h2 class="text-lg font-semibold">Game Room Active</h2>
            <p class="text-sm text-base-content/70 mt-1">Connecting to match engine...</p>
          </div>
        <% else %>
          <div class="card bg-base-200/50 p-8 text-center rounded-2xl border border-base-300">
            <h2 class="text-lg font-semibold text-error">Room Not Found</h2>
            <p class="text-sm text-base-content/70 mt-1">
              This game room may have expired or does not exist.
            </p>
            <div class="mt-4">
              <.link navigate={~p"/"} class="btn btn-primary btn-sm">
                Return to Lobby
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
