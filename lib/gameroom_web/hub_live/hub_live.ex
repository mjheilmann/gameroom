defmodule GameroomWeb.HubLive do
  use GameroomWeb, :live_view

  alias GameroomWeb.Presence
  alias Gameroom.Player
  alias Gameroom.Game

  @presence "gameroom:lobby"

  @games [
    %Game{
      name: "Tic Tac Toe",
      path: "tictactoe",
      module: GameroomWeb.TicTac,
      lobby: "gameroom:lobby:tictactoe"
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

      <p>online users: <%= map_size(@online_users) %></p>
      <%= for {_, user} <- @online_users do %>
        <%= live_component GameroomWeb.PlayerComponent, user: user, my_id: @user.id %>
      <% end %>

      <p>lobby users: <%= map_size(@lobby_users) %></p>
      <%= for {_, user} <- @lobby_users do %>
        <%= live_component GameroomWeb.PlayerComponent, user: user, my_id: @user.id %>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_params(%{"game" => ""}, _uri, socket) do
    user = change_game_lobby(socket.assigns.user, nil)

    Presence.update(self(), @presence, user.id, user)
    {:noreply, assign(socket, :user, user)}
  end

  def handle_params(%{"game" => game_path}, _uri, socket) do
    game =
      socket.assigns.games
      |> Enum.filter(fn %{path: candidate_path} -> candidate_path == game_path end)
      |> List.first()

    user = change_game_lobby(socket.assigns.user, game)
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

    # asynchronous setup
    send(self(), :after_join)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:games, @games)
     |> assign(:online_users, %{user.id => user})
     |> assign(:lobby_users, %{})}
  end

  @impl true
  def handle_info({:subscribe, channel}, %{assigns: %{user: user}} = socket) do
    socket
    |> connected?()
    |> case do
      true ->
        # register ourselves in presence
        {:ok, _} = Presence.track(self(), channel, user.id, user)
        # subscribe to updates
        GameroomWeb.Endpoint.subscribe(channel)

        # populate socket with current list
        {:noreply,
         socket
         |> assign(:lobby_users, %{user.id => user})
         |> handle_joins(Presence.list(channel), :lobby)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:unsubscribe, channel}, %{assigns: %{user: user}} = socket) do
    Presence.untrack(self(), channel, user.id)
    GameroomWeb.Endpoint.unsubscribe(channel)
    {:noreply, assign(socket, :lobby_users, %{})}
  end

  @impl true
  def handle_info(:after_join, %{assigns: %{user: user}} = socket) do
    if connected?(socket) do
      {:ok, _} = Presence.track(self(), @presence, user.id, user)

      GameroomWeb.Endpoint.subscribe(@presence)

      {:noreply,
       socket
       |> assign(:online_users, %{user.id => user})
       |> handle_joins(Presence.list(@presence), :online)}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff, topic: @presence},
        socket
      ) do
    {
      :noreply,
      socket
      |> handle_leaves(diff.leaves, :online)
      |> handle_joins(diff.joins, :online)
    }
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff},
        socket
      ) do
    {
      :noreply,
      socket
      |> handle_leaves(diff.leaves, :lobby)
      |> handle_joins(diff.joins, :lobby)
    }
  end

  defp handle_joins(socket, joins, :online) do
    Enum.reduce(joins, socket, fn {user, %{metas: [meta | _]}}, socket ->
      assign(socket, :online_users, Map.put(socket.assigns.online_users, user, meta))
    end)
  end

  defp handle_joins(socket, joins, :lobby) do
    Enum.reduce(joins, socket, fn {user, %{metas: [meta | _]}}, socket ->
      assign(socket, :lobby_users, Map.put(socket.assigns.lobby_users, user, meta))
    end)
  end

  defp handle_leaves(socket, leaves, :online) do
    Enum.reduce(leaves, socket, fn {user, _}, socket ->
      assign(socket, :online_users, Map.delete(socket.assigns.online_users, user))
    end)
  end

  defp handle_leaves(socket, leaves, :lobby) do
    Enum.reduce(leaves, socket, fn {user, _}, socket ->
      assign(socket, :lobby_users, Map.delete(socket.assigns.lobby_users, user))
    end)
  end

  defp change_game_lobby(%Player{game: nil} = player, nil), do: player

  defp change_game_lobby(%Player{game: nil} = player, %Game{lobby: lobby} = game) do
    send(self(), {:subscribe, lobby})
    %Player{player | game: game}
  end

  defp change_game_lobby(%Player{game: %Game{lobby: lobby}} = player, game) do
    send(self(), {:unsubscribe, lobby})

    change_game_lobby(%Player{player | game: nil}, game)
  end
end
