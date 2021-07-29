defmodule GameroomWeb.TicTac do
  use Phoenix.LiveComponent

  @pieces [:x, :o]
  @initial_board [nil, nil, nil, nil, nil, nil, nil, nil, nil]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, my_turn: false, board: @initial_board)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="" id="<%= @id %>">
    <h4>Tic Tac Toe</h4>
      <section class="column">
        <%= for row <- @board |> Enum.with_index |> Enum.chunk_every(3) do %>
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
    </div>
    """
  end

  @impl true
  def handle_event("inc_try_me", _value, socket) do
    new_try_me_num = socket.assigns.try_me_counter + 1
    socket = assign(socket, :try_me_counter, new_try_me_num)
    {:noreply, socket}
  end

  @impl true
  def handle_event("move", %{"position" => pos}, socket) do
    index = String.to_integer(pos)

    board =
      socket.assigns.board
      |> Enum.at(index, :err)
      |> case do
        nil ->
          socket.assigns.board
          |> List.replace_at(index, :x)

        _ ->
          socket.assigns.board
      end

    if checkwin(board) do
      IO.puts("winner")
    end

    {:noreply, assign(socket, :board, board)}
  end

  defp checkwin([x, x, x, _, _, _, _, _, _]) when x in @pieces, do: true
  defp checkwin([_, _, _, x, x, x, _, _, _]) when x in @pieces, do: true
  defp checkwin([_, _, _, _, _, _, x, x, x]) when x in @pieces, do: true
  defp checkwin([x, _, _, x, _, _, x, _, _]) when x in @pieces, do: true
  defp checkwin([_, x, _, _, x, _, _, x, _]) when x in @pieces, do: true
  defp checkwin([_, _, x, _, _, x, _, _, x]) when x in @pieces, do: true
  defp checkwin([x, _, _, _, x, _, _, _, x]) when x in @pieces, do: true
  defp checkwin([_, _, x, _, x, _, x, _, _]) when x in @pieces, do: true

  defp checkwin(_), do: false
end
