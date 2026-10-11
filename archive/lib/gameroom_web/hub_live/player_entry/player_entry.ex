defmodule GameroomWeb.PlayerEntry do
  use GameroomWeb, :live_component
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "players" do
    field(:name, :string)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [:name])
    |> validate_required([:name])
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~L"""
    <div class="" id="player-entry-<%= @user_id %>">
      <h4>New Player</h4>
        <%= f = form_for @changeset, "#", phx_change: :validate, phx_submit: :save, phx_target: @myself %>
          <%= label f, :name %>
          <%= text_input f, :name %>
          <%= error_tag f, :name %>

          <%= submit "Save" %>
      </form>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:player, %__MODULE__{})
     |> assign(:changeset, changeset(%__MODULE__{}, %{}))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"player_entry" => params}, socket) do
    changeset = changeset(%GameroomWeb.PlayerEntry{}, params)
    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"player_entry" => params}, socket) do
    socket.assigns.player
    |> changeset(params)
    |> case do
      %{valid?: true, changes: %{name: name}} ->
        send(self(), {:set_name, name})

      _ ->
        nil
    end

    {:noreply, socket}
  end
end
