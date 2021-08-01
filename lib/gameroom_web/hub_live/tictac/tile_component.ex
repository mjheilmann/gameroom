defmodule GameroomWeb.TicTac.TileComponent do
  use Phoenix.LiveComponent

  @impl true
  def render(%{content: {:x, _}} = assigns) do
    ~L"""
    <p>[x]<p>
    """
  end

  @impl true
  def render(%{content: {:o, _}} = assigns) do
    ~L"""
    <p>[o]<p>
    """
  end

  @impl true
  def render(%{content: {nil, pos}} = assigns) do
    ~L"""
    <p phx-click="move" phx-target="#<%= @board_id %>" phx-value-position="<%= pos %>">[ ]<p>
    """
  end
end
