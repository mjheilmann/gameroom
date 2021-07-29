defmodule GameroomWeb.TicTac do
  use Phoenix.LiveComponent

  @characters [:x, :o]
  @initial_board [nil, nil, nil, nil, nil, nil, nil, nil, nil]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, try_me_counter: 0, board: @initial_board)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="" id="<%= @id %>">
      <div>
        <h1>tic tac my honkies</h1>
        <button phx-click="inc_try_me" phx-target="<%= @myself %>">Try Me</button> <span>counter: <%= @try_me_counter %></span>
      </div>

      <section class="column">
        <%= for row <- @board |> Enum.with_index |> Enum.chunk_every(3) do %>
          <article class="row">
            <%= for {_, pos} = square <- row do %>
              <%= live_component GameroomWeb.TicTac.TileComponent, id: pos, content: square, board_id: @id %>
            <% end %>
          </article>
        <% end %>
      </section>
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

    {:noreply, assign(socket, :board, board)}
  end
end
