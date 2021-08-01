defmodule GameroomWeb.PlayerComponent do
  use GameroomWeb, :live_component

  @impl true
  def render(%{my_id: my_id, user: %{id: user_id}} = assigns) when my_id == user_id do
    ~L"""
    <div>
      <p class="text-xs bg-green-200 rounded px-2 py-1">~~ <%= @user.name %> (me) ~~ <%= get_game_name(@user) %></p>
    </div>
    """
  end

  def render(assigns) do
    ~L"""
    <div>
      <p class="text-xs bg-blue-200 rounded px-2 py-1">~~ <%= @user.name %> ~~ <%= get_game_name(@user) %></p>
    </div>
    """
  end

  defp get_game_name(%Gameroom.Player{game: nil}), do: ""
  defp get_game_name(%Gameroom.Player{game: %{name: name}}), do: name
end
