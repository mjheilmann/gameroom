defmodule GameroomWeb.TicTac do
  use GameroomWeb, :live_component

  alias Gameroom.Games.Tictactoe

  @impl true
  def mount(socket) do
    {:ok, assign(socket, my_turn: false, board: Tictactoe.new_board())}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="" id="<%= @id %>">
      <h4>Tic Tac Toe</h4>
      <section class="column">
        <%= for row <- @board.places |> Enum.with_index |> Enum.chunk_every(3) do %>
          <article class="row">
            <%= for {_, pos} = square <- row do %>
              <%= live_component GameroomWeb.TicTac.TileComponent, id: pos, content: square, board_id: @id %>
            <% end %>
          </article>
        <% end %>
      </section>
      <%= if @my_turn do %>
        <p>It is your turn</p>
      <% else %>
        <p>It is NOT your turn</p>
      <% end %>
      <%= live_patch "leave", to: Routes.live_path(@socket, GameroomWeb.HubLive, game: nil) %>
    </div>
    """
  end

  @impl true
  def handle_event("move", %{"position" => pos}, socket) do
    with {int_pos, _} <- Integer.parse(pos),
         {:ok, board} <- Tictactoe.move(socket.assigns.board, :x, int_pos) do
      win_or_continue(assign(socket, :board, board))
    else
      _ -> {:noreply, socket}
    end
  end

  def win_or_continue(socket) do
    if Tictactoe.winner?(socket.assigns.board, :x) do
      {:noreply, assign(socket, :result, :win)}
    else
      {:noreply, socket}
    end
  end
end
