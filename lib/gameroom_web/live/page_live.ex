defmodule GameroomWeb.PageLive do
  use GameroomWeb, :live_view

  @games [["Tic Tac Toe", GameroomWeb.TicTac]]

  @impl true
  def render(assigns) do
    ~L"""
    <section class="phx-hero">
    <%= live_component GameroomWeb.TicTac, id: "tictac-5" %>
    </section>
    """
  end
end
