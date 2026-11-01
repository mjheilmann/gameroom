defmodule Gameroom.Games do
  @moduledoc """
  Public context facade for GameRoom games, rooms, and matchmaking.

  Provides a clean boundary for LiveViews and external callers to interact
  with supervised game room processes, query lobby listings, and subscribe to events.
  """

  alias Gameroom.Games.Room
  alias Gameroom.Games.RoomSupervisor
  alias Gameroom.Games.RoomRegistry

  @default_pubsub Gameroom.PubSub

  @adjectives ~w(swift clever cosmic brave mighty golden silent lucky stellar neon epic rapid bright bold wild zen astral hyper sonic nimble prime)
  @nouns ~w(otter falcon panda fox badger tiger lynx hawk wolf koala gecko bison phoenix dragon viper bear eagle cheetah raven cobra)

  @doc """
  Creates and starts a new game room. If no `room_id` is specified or empty, generates a readable unique slug.

  Returns `{:ok, room_id}` on success or `{:error, reason}` on failure.
  """
  @spec create_room(String.t() | nil, keyword() | map()) ::
          {:ok, String.t()} | {:error, term()}
  def create_room(room_id \\ nil, opts \\ []) do
    opts_map = Map.new(opts)

    cleaned_id =
      case room_id do
        nil ->
          generate_room_id()

        id when is_binary(id) ->
          trimmed = String.trim(id)
          if trimmed == "", do: generate_room_id(), else: trimmed

        _ ->
          generate_room_id()
      end

    opts_map = Map.put(opts_map, :room_id, cleaned_id)

    case RoomSupervisor.start_room(opts_map) do
      {:ok, _pid} -> {:ok, cleaned_id}
      {:error, {:already_started, _pid}} -> {:error, :already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stops an active room.
  """
  defdelegate stop_room(room_id_or_pid, reason \\ :normal), to: RoomSupervisor

  @doc """
  Checks if a room exists and is currently running.
  """
  defdelegate room_exists?(room_id_or_pid), to: RoomSupervisor

  @doc """
  Returns the PID of a room by room_id or PID.
  """
  defdelegate get_room_pid(room_id_or_pid), to: RoomSupervisor, as: :room_pid

  @doc """
  Returns the count of active room processes.
  """
  defdelegate count_rooms(), to: RoomSupervisor

  @doc """
  Gets the full state of a room.
  """
  @spec get_room_state(String.t() | pid(), timeout()) ::
          {:ok, Room.t()} | {:error, term()}
  def get_room_state(room_id_or_pid, timeout \\ 5000) do
    Room.get_state(room_id_or_pid, timeout)
  end

  @doc """
  Gets a lightweight summary of the room.
  """
  @spec get_room_summary(String.t() | pid(), timeout()) ::
          {:ok, map()} | {:error, term()}
  def get_room_summary(room_id_or_pid, timeout \\ 5000) do
    Room.get_summary(room_id_or_pid, timeout)
  end

  @doc """
  Lists all active rooms, ordered with newest rooms first.
  Optimized using `RoomRegistry` metadata cache with fallback to GenServer.
  """
  @spec list_rooms() :: [map()]
  def list_rooms do
    entries =
      Registry.select(RoomRegistry, [
        {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
      ])

    now = DateTime.utc_now()

    entries
    |> Enum.filter(fn {_id, pid, _val} -> Process.alive?(pid) end)
    |> Enum.map(fn {room_id, pid, value} ->
      if is_map(value) do
        value
      else
        case Room.get_summary(pid) do
          {:ok, summary} ->
            summary

          _ ->
            %{
              room_id: room_id,
              status: :waiting,
              player_count: 0,
              spectator_count: 0,
              inserted_at: now
            }
        end
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&Map.get(&1, :inserted_at, now), {:desc, DateTime})
  end

  @doc """
  Joins a player to a room.
  """
  @spec join_room(
          String.t() | pid(),
          String.t(),
          String.t(),
          atom() | String.t() | nil,
          timeout()
        ) ::
          {:ok, map()} | {:error, term()}
  def join_room(room_id_or_pid, player_id, player_name, requested_role \\ nil, timeout \\ 5000) do
    Room.join(room_id_or_pid, player_id, player_name, requested_role, timeout)
  end

  @doc """
  Removes a player from a room.
  """
  @spec leave_room(String.t() | pid(), String.t(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def leave_room(room_id_or_pid, player_id, timeout \\ 5000) do
    Room.leave(room_id_or_pid, player_id, timeout)
  end

  @doc """
  Plays a move in the game room.
  """
  @spec play_move(String.t() | pid(), String.t(), term(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def play_move(room_id_or_pid, player_id, move, timeout \\ 5000) do
    Room.play_move(room_id_or_pid, player_id, move, timeout)
  end

  @doc """
  Votes for a rematch when a game is finished.
  """
  @spec rematch(String.t() | pid(), String.t(), timeout()) ::
          {:ok, :rematch_requested | :rematch_started} | {:error, term()}
  def rematch(room_id_or_pid, player_id, timeout \\ 5000) do
    Room.rematch(room_id_or_pid, player_id, timeout)
  end

  @doc """
  Resets a game room to a fresh game state.
  """
  @spec reset_room(String.t() | pid(), keyword(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def reset_room(room_id_or_pid, opts \\ [], timeout \\ 5000) do
    Room.reset_game(room_id_or_pid, opts, timeout)
  end

  @doc """
  Promotes a spectator to an open seat.
  """
  def take_seat(room_id_or_pid, player_id, requested_role \\ nil, timeout \\ 5000) do
    Room.take_seat(room_id_or_pid, player_id, requested_role, timeout)
  end

  @doc """
  Switches a seated player to spectator mode.
  """
  def switch_to_spectator(room_id_or_pid, player_id, timeout \\ 5000) do
    Room.switch_to_spectator(room_id_or_pid, player_id, timeout)
  end

  @doc """
  Forfeits the game for a seated player.
  """
  def forfeit(room_id_or_pid, player_id, timeout \\ 5000) do
    Room.forfeit(room_id_or_pid, player_id, timeout)
  end

  @doc """
  Subscribes caller to events for a specific room (`\"room:<room_id>\"`).
  """
  @spec subscribe(String.t(), module() | atom()) :: :ok | {:error, term()}
  def subscribe(room_id, pubsub \\ @default_pubsub) do
    Phoenix.PubSub.subscribe(pubsub, "room:#{room_id}")
  end

  @doc """
  Unsubscribes caller from events for a specific room.
  """
  @spec unsubscribe(String.t(), module() | atom()) :: :ok | {:error, term()}
  def unsubscribe(room_id, pubsub \\ @default_pubsub) do
    Phoenix.PubSub.unsubscribe(pubsub, "room:#{room_id}")
  end

  @doc """
  Subscribes caller to lobby updates (`\"rooms:lobby\"`).
  """
  @spec subscribe_lobby(module() | atom()) :: :ok | {:error, term()}
  def subscribe_lobby(pubsub \\ @default_pubsub) do
    Phoenix.PubSub.subscribe(pubsub, "rooms:lobby")
  end

  @doc """
  Unsubscribes caller from lobby updates.
  """
  @spec unsubscribe_lobby(module() | atom()) :: :ok | {:error, term()}
  def unsubscribe_lobby(pubsub \\ @default_pubsub) do
    Phoenix.PubSub.unsubscribe(pubsub, "rooms:lobby")
  end

  @doc """
  Generates a friendly unique room slug (e.g. `\"cosmic-falcon-42\"`).
  """
  @spec generate_room_id() :: String.t()
  def generate_room_id do
    adj = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    num = :rand.uniform(90) + 9
    "#{adj}-#{noun}-#{num}"
  end
end
