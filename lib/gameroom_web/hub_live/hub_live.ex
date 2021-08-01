defmodule GameroomWeb.HubLive do
  use GameroomWeb, :live_view

  alias GameroomWeb.Presence
  alias Gameroom.Player
  alias Gameroom.Game

  @presence "gameroom:presence"

  @games [
    %Game{
      name: "Tic Tac Toe",
      path: "tictactoe",
      module: GameroomWeb.TicTac
    }
  ]

  @impl true
  def render(assigns) do
    ~L"""
    <section class="phx-hero">
      <%= if is_nil(@user.game) do %>
        <%= live_component GameroomWeb.GameSelector, available_games: @games, user_id: @user.id %>
      <% else %>
        <%= live_component @user.game.module, id: "game-" <> @user.id, user_id: @user.id %>
      <% end %>

      <p>users: <%= map_size(@users) %></p>
      <%= for {_, user} <- @users do %>
        <%= live_component GameroomWeb.PlayerComponent, user: user, my_id: @user.id %>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_params(%{"game" => ""}, _uri, socket) do
    user = Map.put(socket.assigns.user, :game, nil)

    Presence.update(self(), @presence, user.id, user)
    {:noreply, assign(socket, :user, user)}
  end

  def handle_params(%{"game" => game_path}, _uri, socket) do
    game =
      socket.assigns.games
      |> Enum.filter(fn %{path: candidate_path} -> candidate_path == game_path end)
      |> List.first()

    user = %Player{socket.assigns.user | game: game}
    Presence.update(self(), @presence, user.id, user)
    {:noreply, assign(socket, :user, user)}
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  @impl true
  def mount(_params, _session, socket) do
    user = %Player{
      id: Nanoid.generate(),
      game: nil,
      name: "wallace",
      joined_at: :os.system_time(:seconds)
    }

    socket =
      socket
      |> assign(:user, user)
      |> assign(:games, @games)
      |> assign(:users, %{})
      |> handle_joins(Presence.list(@presence))

    if connected?(socket) do
      {:ok, _} = Presence.track(self(), @presence, user.id, user)

      GameroomWeb.Endpoint.subscribe(@presence)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    {
      :noreply,
      socket
      |> handle_leaves(diff.leaves)
      |> handle_joins(diff.joins)
    }
  end

  defp handle_joins(socket, joins) do
    Enum.reduce(joins, socket, fn {user, %{metas: [meta | _]}}, socket ->
      assign(socket, :users, Map.put(socket.assigns.users, user, meta))
    end)
  end

  defp handle_leaves(socket, leaves) do
    Enum.reduce(leaves, socket, fn {user, _}, socket ->
      assign(socket, :users, Map.delete(socket.assigns.users, user))
    end)
  end
end
