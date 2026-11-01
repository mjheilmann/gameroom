defmodule GameroomWeb.HubLive do
  @moduledoc """
  Real-time Hub and Lobby for GameRoom.

  Provides active presence tracking, player nickname management, live room browsing
  with real-time PubSub updates, and fast game room creation.
  """
  use GameroomWeb, :live_view

  alias Gameroom.Games
  alias GameroomWeb.Presence

  @presence_topic "lobby:presence"

  @impl true
  def mount(_params, session, socket) do
    player_id = session["player_id"] || Ecto.UUID.generate()
    player_name = session["player_name"] || Games.generate_player_name()

    if connected?(socket) do
      Games.subscribe_lobby()
      Phoenix.PubSub.subscribe(Gameroom.PubSub, @presence_topic)

      {:ok, _} =
        Presence.track(self(), @presence_topic, player_id, %{
          id: player_id,
          nickname: player_name,
          joined_at: System.system_time(:second)
        })
    end

    presences = if connected?(socket), do: Presence.list(@presence_topic), else: %{}
    online_count = map_size(presences)
    online_players = extract_presence_users(presences)

    rooms = Games.list_rooms()

    default_room_id = Games.generate_room_id()
    create_form = to_form(%{"room_id" => default_room_id, "role" => "x"}, as: :room)
    nickname_form = to_form(%{"nickname" => player_name}, as: :player)

    {:ok,
     socket
     |> assign(
       page_title: "GameRoom · Real-Time Tabletop Hub",
       player_id: player_id,
       current_player_name: player_name,
       editing_nickname?: false,
       nickname_form: nickname_form,
       create_form: create_form,
       filter: :all,
       search_query: "",
       presences: presences,
       online_count: max(1, online_count),
       online_players: online_players,
       rooms_count: length(rooms)
     )
     |> stream(:rooms, rooms)}
  end

  @impl true
  def handle_event("edit_nickname", _params, socket) do
    form = to_form(%{"nickname" => socket.assigns.current_player_name}, as: :player)
    {:noreply, assign(socket, editing_nickname?: true, nickname_form: form)}
  end

  def handle_event("cancel_edit_nickname", _params, socket) do
    {:noreply, assign(socket, editing_nickname?: false)}
  end

  def handle_event("save_nickname", %{"player" => %{"nickname" => nickname_param}}, socket) do
    clean_name = String.trim(nickname_param)
    len = String.length(clean_name)

    if len >= 2 and len <= 24 do
      player_id = socket.assigns.player_id

      if connected?(socket) do
        Presence.update(self(), @presence_topic, player_id, fn meta ->
          Map.put(meta, :nickname, clean_name)
        end)
      end

      form = to_form(%{"nickname" => clean_name}, as: :player)

      {:noreply,
       socket
       |> assign(
         current_player_name: clean_name,
         editing_nickname?: false,
         nickname_form: form
       )
       |> push_event("save_nickname", %{nickname: clean_name})
       |> put_flash(:info, "Nickname updated to \"#{clean_name}\"")}
    else
      form = to_form(%{"nickname" => clean_name}, as: :player)

      {:noreply,
       socket
       |> assign(nickname_form: form)
       |> put_flash(:error, "Nickname must be between 2 and 24 characters.")}
    end
  end

  def handle_event("restore_nickname", %{"nickname" => stored_name}, socket) do
    clean = String.trim(stored_name)

    if clean != "" and clean != socket.assigns.current_player_name and String.length(clean) <= 24 do
      player_id = socket.assigns.player_id

      if connected?(socket) do
        Presence.update(self(), @presence_topic, player_id, fn meta ->
          Map.put(meta, :nickname, clean)
        end)
      end

      form = to_form(%{"nickname" => clean}, as: :player)
      {:noreply, assign(socket, current_player_name: clean, nickname_form: form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("randomize_room_id", _params, socket) do
    new_slug = Games.generate_room_id()
    role = socket.assigns.create_form[:role].value || "x"
    form = to_form(%{"room_id" => new_slug, "role" => role}, as: :room)
    {:noreply, assign(socket, create_form: form)}
  end

  def handle_event("validate_create", %{"room" => room_params}, socket) do
    {:noreply, assign(socket, create_form: to_form(room_params, as: :room))}
  end

  def handle_event("create_room", %{"room" => %{"room_id" => room_id_param} = params}, socket) do
    raw_slug = String.trim(room_id_param)
    room_id = if raw_slug == "", do: Games.generate_room_id(), else: raw_slug
    _role = Map.get(params, "role", "x")

    case Games.create_room(room_id, game_module: Games.TicTacToe) do
      {:ok, created_id} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{created_id}")}

      {:error, :already_exists} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "A game room with ID \"#{room_id}\" already exists. Please pick another code."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create room: #{inspect(reason)}")}
    end
  end

  def handle_event("join_by_code", %{"room_code" => raw_code}, socket) do
    clean_code = String.trim(raw_code)

    if clean_code != "" do
      {:noreply, push_navigate(socket, to: ~p"/games/#{clean_code}")}
    else
      {:noreply, put_flash(socket, :error, "Please enter a valid room code.")}
    end
  end

  def handle_event("set_filter", %{"filter" => filter_str}, socket) do
    filter =
      case filter_str do
        "waiting" -> :waiting
        "in_progress" -> :in_progress
        "finished" -> :finished
        _ -> :all
      end

    all_rooms = Games.list_rooms()
    filtered = filter_rooms(all_rooms, filter, socket.assigns.search_query)

    {:noreply,
     socket
     |> assign(filter: filter, rooms_count: length(filtered))
     |> stream(:rooms, filtered, reset: true)}
  end

  def handle_event("search_rooms", %{"query" => query}, socket) do
    clean_query = String.trim(query)
    all_rooms = Games.list_rooms()
    filtered = filter_rooms(all_rooms, socket.assigns.filter, clean_query)

    {:noreply,
     socket
     |> assign(search_query: clean_query, rooms_count: length(filtered))
     |> stream(:rooms, filtered, reset: true)}
  end

  # ---------------------------------------------------------------------------
  # PubSub Info Handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:room_created, summary}, socket) do
    if matches_filters?(summary, socket.assigns.filter, socket.assigns.search_query) do
      {:noreply,
       socket
       |> assign(rooms_count: socket.assigns.rooms_count + 1)
       |> stream_insert(:rooms, summary, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:room_updated, summary}, socket) do
    if matches_filters?(summary, socket.assigns.filter, socket.assigns.search_query) do
      {:noreply, stream_insert(socket, :rooms, summary)}
    else
      {:noreply, stream_delete(socket, :rooms, summary)}
    end
  end

  def handle_info({:room_deleted, %{room_id: room_id}}, socket) do
    {:noreply,
     socket
     |> assign(rooms_count: max(0, socket.assigns.rooms_count - 1))
     |> stream_delete(:rooms, %{id: room_id})}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    presences = Presence.handle_diff(socket.assigns.presences, diff)
    online_count = map_size(presences)
    online_players = extract_presence_users(presences)

    {:noreply,
     assign(socket,
       presences: presences,
       online_count: max(1, online_count),
       online_players: online_players
     )}
  end

  # ---------------------------------------------------------------------------
  # Template Rendering
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} container_class="mx-auto max-w-6xl space-y-8">
      <div id="nickname-storage" phx-hook="NicknameStorage" class="space-y-8">
        <%!-- Hero Banner & Presence Header --%>
        <div class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-base-200/90 via-base-200/40 to-base-100 p-6 sm:p-10 border border-base-300 shadow-sm">
          <div class="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div class="space-y-2">
              <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 border border-primary/20 text-primary text-xs font-semibold">
                <.icon name="hero-bolt" class="size-3.5" />
                <span>Real-Time Elixir & LiveView Engine</span>
              </div>
              <h1 class="text-3xl sm:text-4xl font-extrabold tracking-tight">
                Tabletop Games Lobby
              </h1>
              <p class="text-base text-base-content/70 max-w-xl">
                Play instant multiplayer board games in your browser. Create a match, invite friends, or join active games with live spectators.
              </p>
            </div>

            <%!-- Player Identity & Presence Pill --%>
            <div class="flex flex-col sm:flex-row items-start sm:items-center gap-4 bg-base-100/80 backdrop-blur p-4 rounded-2xl border border-base-300 shadow-xs">
              <div class="flex items-center gap-3">
                <div class="size-11 rounded-xl bg-gradient-to-tr from-primary to-accent text-primary-content flex items-center justify-center font-bold text-lg shadow-xs">
                  {String.first(@current_player_name) || "P"}
                </div>
                <div>
                  <div class="text-xs text-base-content/60 font-medium">Your Nickname</div>
                  <%= if @editing_nickname? do %>
                    <.form
                      for={@nickname_form}
                      id="nickname-form"
                      phx-submit="save_nickname"
                      class="flex items-center gap-1.5 mt-0.5"
                    >
                      <.input
                        field={@nickname_form[:nickname]}
                        type="text"
                        class="input input-xs w-36 font-semibold"
                        required
                        autofocus
                      />
                      <button
                        type="submit"
                        id="save-nickname-btn"
                        class="btn btn-primary btn-xs"
                        title="Save"
                      >
                        <.icon name="hero-check" class="size-3" />
                      </button>
                      <button
                        type="button"
                        id="cancel-nickname-btn"
                        phx-click="cancel_edit_nickname"
                        class="btn btn-ghost btn-xs"
                        title="Cancel"
                      >
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    </.form>
                  <% else %>
                    <div class="flex items-center gap-2">
                      <span id="player-nickname-display" class="font-bold text-sm">
                        {@current_player_name}
                      </span>
                      <button
                        type="button"
                        id="edit-nickname-btn"
                        phx-click="edit_nickname"
                        class="btn btn-ghost btn-xs size-6 p-0 text-base-content/60 hover:text-primary"
                        aria-label="Edit nickname"
                      >
                        <.icon name="hero-pencil" class="size-3.5" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>

              <div class="h-8 w-px bg-base-300 hidden sm:block"></div>

              <div class="flex items-center gap-2 text-xs font-semibold px-2.5 py-1.5 rounded-lg bg-success/10 text-success">
                <span class="size-2 rounded-full bg-success animate-pulse"></span>
                <span id="online-players-count">{@online_count} Online</span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Quick Actions Section: Create & Join --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Create Room Card (Spans 2 cols) --%>
          <div class="lg:col-span-2 rounded-2xl bg-base-100 p-6 border border-base-200 shadow-xs space-y-4">
            <div class="flex items-center justify-between pb-2 border-b border-base-200">
              <div class="flex items-center gap-2.5">
                <div class="size-8 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
                  <.icon name="hero-plus" class="size-5" />
                </div>
                <div>
                  <h2 class="font-bold text-base">Create New Game</h2>
                  <p class="text-xs text-base-content/60">Launch an instant Tic-Tac-Toe room</p>
                </div>
              </div>
              <span class="badge badge-primary badge-sm font-semibold">Instant Play</span>
            </div>

            <.form
              for={@create_form}
              id="create-room-form"
              phx-submit="create_room"
              phx-change="validate_create"
              class="space-y-4"
            >
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-base-content/80 mb-1.5">
                    Room Code / Slug
                  </label>
                  <div class="flex items-center gap-2">
                    <div class="flex-1">
                      <.input
                        field={@create_form[:room_id]}
                        type="text"
                        class="input input-sm w-full font-mono text-sm"
                        placeholder="e.g. swift-otter-42"
                        required
                      />
                    </div>
                    <button
                      type="button"
                      id="randomize-slug-btn"
                      phx-click="randomize_room_id"
                      class="btn btn-outline btn-sm"
                      title="Randomize Room Code"
                    >
                      <.icon name="hero-arrow-path" class="size-4" />
                    </button>
                  </div>
                </div>

                <div>
                  <label class="block text-xs font-semibold text-base-content/80 mb-1.5">
                    Your Starting Seat
                  </label>
                  <.input
                    field={@create_form[:role]}
                    type="select"
                    class="select select-sm w-full text-sm font-medium"
                    options={[
                      {"Seat X (Plays First)", "x"},
                      {"Seat O (Plays Second)", "o"},
                      {"Spectate First", "spectator"}
                    ]}
                  />
                </div>
              </div>

              <div class="flex flex-col sm:flex-row items-center justify-between gap-4 pt-2">
                <div class="flex items-center gap-2 text-xs text-base-content/60">
                  <.icon name="hero-information-circle" class="size-4 text-primary" />
                  <span>Rooms automatically pause and clean up when idle.</span>
                </div>
                <button
                  type="submit"
                  id="submit-create-room"
                  class="btn btn-primary btn-sm w-full sm:w-auto font-semibold px-6 shadow-xs"
                >
                  <.icon name="hero-play" class="size-4 mr-1" /> Create & Launch Game
                </button>
              </div>
            </.form>
          </div>

          <%!-- Direct Join by Code Card --%>
          <div class="rounded-2xl bg-base-100 p-6 border border-base-200 shadow-xs space-y-4 flex flex-col justify-between">
            <div>
              <div class="flex items-center gap-2.5 pb-2 border-b border-base-200">
                <div class="size-8 rounded-lg bg-accent/10 text-accent flex items-center justify-center">
                  <.icon name="hero-arrow-right-end-on-rectangle" class="size-5" />
                </div>
                <div>
                  <h2 class="font-bold text-base">Join with Code</h2>
                  <p class="text-xs text-base-content/60">Enter an invite code from a friend</p>
                </div>
              </div>

              <form id="join-code-form" phx-submit="join_by_code" class="mt-4 space-y-3">
                <div>
                  <label class="block text-xs font-semibold text-base-content/80 mb-1.5">
                    Room Code
                  </label>
                  <input
                    type="text"
                    name="room_code"
                    id="join-room-code-input"
                    class="input input-sm w-full font-mono text-sm"
                    placeholder="e.g. swift-otter-42"
                    required
                  />
                </div>
                <button
                  type="submit"
                  id="submit-join-code"
                  class="btn btn-accent btn-sm w-full font-semibold shadow-xs"
                >
                  <.icon name="hero-arrow-right" class="size-4 mr-1" /> Enter Room
                </button>
              </form>
            </div>

            <div class="pt-3 border-t border-base-200/60 text-xs text-base-content/60 flex items-center justify-between">
              <span>Game Catalog:</span>
              <span class="badge badge-ghost badge-xs font-semibold">Tic-Tac-Toe</span>
            </div>
          </div>
        </div>

        <%!-- Active Rooms Browser Section --%>
        <div class="space-y-4">
          <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div class="flex items-center gap-2">
              <h2 class="text-xl font-bold tracking-tight">Active Game Rooms</h2>
              <span
                id="active-rooms-count"
                class="badge badge-neutral badge-sm font-semibold px-2 py-0.5"
              >
                {@rooms_count}
              </span>
            </div>

            <%!-- Filters & Search Toolbar --%>
            <div class="flex flex-wrap items-center gap-2.5 w-full sm:w-auto">
              <div class="join">
                <button
                  type="button"
                  id="filter-all-btn"
                  phx-click="set_filter"
                  phx-value-filter="all"
                  class={["join-item btn btn-xs", @filter == :all && "btn-active btn-neutral"]}
                >
                  All
                </button>
                <button
                  type="button"
                  id="filter-waiting-btn"
                  phx-click="set_filter"
                  phx-value-filter="waiting"
                  class={["join-item btn btn-xs", @filter == :waiting && "btn-active btn-neutral"]}
                >
                  Waiting
                </button>
                <button
                  type="button"
                  id="filter-in-progress-btn"
                  phx-click="set_filter"
                  phx-value-filter="in_progress"
                  class={[
                    "join-item btn btn-xs",
                    @filter == :in_progress && "btn-active btn-neutral"
                  ]}
                >
                  In Progress
                </button>
                <button
                  type="button"
                  id="filter-finished-btn"
                  phx-click="set_filter"
                  phx-value-filter="finished"
                  class={[
                    "join-item btn btn-xs",
                    @filter == :finished && "btn-active btn-neutral"
                  ]}
                >
                  Finished
                </button>
              </div>

              <form id="search-rooms-form" phx-change="search_rooms" class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="size-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-base-content/40"
                />
                <input
                  type="text"
                  name="query"
                  id="search-rooms-input"
                  value={@search_query}
                  placeholder="Search rooms..."
                  class="input input-xs pl-8 w-36 sm:w-44"
                />
              </form>
            </div>
          </div>

          <%!-- Rooms List (LiveView Stream) --%>
          <div
            id="rooms-stream"
            phx-update="stream"
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <div
              :for={{dom_id, room} <- @streams.rooms}
              id={dom_id}
              class="card bg-base-100 rounded-2xl border border-base-200 hover:border-primary/40 shadow-xs hover:shadow-md transition-all duration-200 flex flex-col justify-between overflow-hidden"
            >
              <div class="p-5 space-y-4">
                <%!-- Room Header: ID & Status Badge --%>
                <div class="flex items-start justify-between gap-2">
                  <div class="space-y-0.5">
                    <span class="font-mono font-bold text-sm tracking-tight text-base-content">
                      {room.room_id}
                    </span>
                    <div class="text-xs text-base-content/50 font-medium">Tic-Tac-Toe</div>
                  </div>

                  <%= cond do %>
                    <% room.status == :waiting -> %>
                      <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-success/10 text-success">
                        <span class="size-1.5 rounded-full bg-success animate-pulse"></span> Waiting
                      </span>
                    <% room.status == :in_progress -> %>
                      <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-warning/10 text-warning">
                        <span class="size-1.5 rounded-full bg-warning animate-pulse"></span>
                        Turn: {String.upcase(to_string(room.current_player || ""))}
                      </span>
                    <% room.status == :finished -> %>
                      <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-primary/10 text-primary">
                        <%= if room.winner do %>
                          Winner: {String.upcase(to_string(room.winner))}
                        <% else %>
                          Draw
                        <% end %>
                      </span>
                  <% end %>
                </div>

                <%!-- Seats Grid --%>
                <div class="grid grid-cols-2 gap-2 text-xs">
                  <div class="bg-base-200/60 p-2.5 rounded-xl border border-base-300/40">
                    <div class="text-base-content/50 font-bold uppercase tracking-wider text-[10px]">
                      Seat X
                    </div>
                    <div class="font-semibold truncate mt-0.5">
                      {Map.get(room.seats, :x) || "Open Seat"}
                    </div>
                  </div>
                  <div class="bg-base-200/60 p-2.5 rounded-xl border border-base-300/40">
                    <div class="text-base-content/50 font-bold uppercase tracking-wider text-[10px]">
                      Seat O
                    </div>
                    <div class="font-semibold truncate mt-0.5">
                      {Map.get(room.seats, :o) || "Open Seat"}
                    </div>
                  </div>
                </div>

                <%!-- Spectators & Metadata --%>
                <div class="flex items-center justify-between text-xs text-base-content/60 pt-1">
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-eye" class="size-3.5" />
                    <span>{room.spectator_count} spectating</span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-user-group" class="size-3.5" />
                    <span>{room.player_count}/{room.max_players} players</span>
                  </div>
                </div>
              </div>

              <%!-- Action Footer --%>
              <div class="p-3 bg-base-200/40 border-t border-base-200 flex items-center justify-between">
                <%= cond do %>
                  <% room.status == :waiting -> %>
                    <.link
                      navigate={~p"/games/#{room.room_id}"}
                      id={"join-room-btn-#{room.room_id}"}
                      class="btn btn-primary btn-sm w-full font-semibold shadow-xs"
                    >
                      <.icon name="hero-arrow-right-end-on-rectangle" class="size-4 mr-1" />
                      Join Match
                    </.link>
                  <% room.status == :in_progress -> %>
                    <.link
                      navigate={~p"/games/#{room.room_id}"}
                      id={"spectate-room-btn-#{room.room_id}"}
                      class="btn btn-neutral btn-sm w-full font-semibold"
                    >
                      <.icon name="hero-eye" class="size-4 mr-1" /> Spectate Game
                    </.link>
                  <% true -> %>
                    <.link
                      navigate={~p"/games/#{room.room_id}"}
                      id={"view-room-btn-#{room.room_id}"}
                      class="btn btn-ghost btn-sm w-full font-semibold"
                    >
                      View Board & Rematch
                    </.link>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Empty State when no rooms exist --%>
          <%= if @rooms_count == 0 do %>
            <div
              id="empty-rooms-state"
              class="rounded-3xl border border-dashed border-base-300 p-12 text-center space-y-4 bg-base-100/50"
            >
              <div class="size-14 rounded-2xl bg-primary/10 text-primary mx-auto flex items-center justify-center">
                <.icon name="hero-puzzle-piece" class="size-8" />
              </div>
              <div class="space-y-1">
                <h3 class="font-bold text-lg">No active games right now</h3>
                <p class="text-sm text-base-content/60 max-w-sm mx-auto">
                  Be the first player to start a match! Create a room above and share the room code with a friend.
                </p>
              </div>
              <div>
                <button
                  type="button"
                  id="empty-state-randomize-btn"
                  phx-click="randomize_room_id"
                  class="btn btn-primary btn-sm"
                >
                  <.icon name="hero-sparkles" class="size-4 mr-1" /> Generate New Room Code
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp extract_presence_users(presences) do
    Enum.map(presences, fn {id, %{metas: metas}} ->
      first_meta = List.first(metas) || %{}
      %{id: id, nickname: Map.get(first_meta, :nickname, "Guest")}
    end)
  end

  defp filter_rooms(rooms, filter, search_query) do
    rooms
    |> Enum.filter(&matches_filters?(&1, filter, search_query))
  end

  defp matches_filters?(room, filter, search_query) do
    matches_status?(room, filter) and matches_search?(room, search_query)
  end

  defp matches_status?(_room, :all), do: true
  defp matches_status?(room, status), do: room.status == status

  defp matches_search?(_room, ""), do: true

  defp matches_search?(room, query) do
    q = String.downcase(query)
    id_match = String.contains?(String.downcase(room.room_id), q)

    seats_match =
      Enum.any?(room.seats, fn {_role, name} ->
        name && String.contains?(String.downcase(name), q)
      end)

    id_match or seats_match
  end
end
