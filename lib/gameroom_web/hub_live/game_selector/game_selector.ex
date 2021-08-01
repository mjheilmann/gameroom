defmodule GameroomWeb.GameSelector do
  use GameroomWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
    <div class="" id="selector-<%= @user_id %>">
      <h4>Game Selector</h4>
      <%= for %{name: name, path: path} <- @available_games do %>
        <p>
          <%= live_patch name, to: Routes.live_path(@socket, GameroomWeb.HubLive, game: path) %>
        </p>
      <% end %>
    </div>
    """
  end
end
