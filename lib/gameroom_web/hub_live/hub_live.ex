defmodule GameroomWeb.HubLive do
  use GameroomWeb, :live_view

  @games [
    %Gameroom.Game{name: "Tic Tac Toe", path: "tictactoe", module: GameroomWeb.TicTac}
  ]

  @impl true
  def render(assigns) do
    ~L"""
    <section class="phx-hero">
      <%= if is_nil(@selected_game) do %>
        <%= live_component GameroomWeb.GameSelector, available_games: @supported_games, user_id: @user_id %>
      <% else %>
        <%= live_component @selected_game, id: "tictac-5" %>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_params(%{"game" => game}, _uri, socket) do
    socket.assigns.supported_games
    |> Enum.filter(fn %{name: game_name} -> game_name == game end)
    |> case do
      [] ->
        IO.puts("game not found")
        {:noreply, socket}

      [%{module: game_module} | _] ->
        {:noreply, assign(socket, :selected_game, game_module)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:user_id, Nanoid.generate())
      |> assign(:selected_game, nil)
      |> assign(:supported_games, @games)

    {:ok, socket}
  end
end
