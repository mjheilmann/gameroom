defmodule GameroomWeb.HubLive do
  use GameroomWeb, :live_view

  alias GameroomWeb.Presence

  @presence "gameroom:presence"

  @games [
    %Gameroom.Game{
      name: "Tic Tac Toe",
      path: "tictactoe",
      module: GameroomWeb.TicTac
    }
  ]

  @impl true
  def render(assigns) do
    ~L"""
    <section class="phx-hero">
      <%= if is_nil(@selected_game) do %>
        <%= live_component GameroomWeb.GameSelector, available_games: @supported_games, user_id: @user_id %>
      <% else %>
        <%= live_component @selected_game, user_id: @user_id %>
      <% end %>
    <p>users: <%= map_size(@users) %></p>
    <%= for {user_id, user} <- @users do %>
      <%= if user_id == @user_id do %>
        <p class="text-xs bg-green-200 rounded px-2 py-1">~~ <%= user[:name] %> (me)</p>
      <% else %>
        <p class="text-xs bg-blue-200 rounded px-2 py-1">~~ <%= user[:name] %></p>
      <% end %>
    <% end %>
    </section>
    """
  end

  @impl true
  def handle_params(%{"game" => ""}, _uri, socket) do
    {:noreply, assign(socket, :selected_game, nil)}
  end

  def handle_params(%{"game" => game}, _uri, socket) do
    socket.assigns.supported_games
    |> Enum.filter(fn %{name: game_name} -> game_name == game end)
    |> case do
      [] ->
        {:noreply, assign(socket, :selected_game, nil)}

      [%{module: game_module} | _] ->
        {:noreply, assign(socket, :selected_game, game_module)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    user_id = Nanoid.generate()

    if connected?(socket) do
      {:ok, _} =
        Presence.track(self(), @presence, user_id, %{
          name: "wallace",
          joined_at: :os.system_time(:seconds)
        })

      GameroomWeb.Endpoint.subscribe(@presence)
    end

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:selected_game, nil)
     |> assign(:supported_games, @games)
     |> assign(:users, %{})
     |> handle_joins(Presence.list(@presence))}
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
