defmodule GameroomWeb.GameSelector do
  use GameroomWeb, :live_component

  @impl true
  def render(assigns) do
    IO.inspect(Routes)

    ~L"""
    <div class="" id="selector-<%= @user_id %>">
      <h4>Game Selector</h4>
      <%= for %{name: name} <- @available_games do %>
        <p>
          <%= live_patch name, to: Routes.live_path(@socket, GameroomWeb.HubLive, game: name) %>
        </p>
      <% end %>
    </div>
    """
  end
end
