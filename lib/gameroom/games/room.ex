defmodule Gameroom.Games.Room do
  @moduledoc """
  GenServer managing state and real-time interaction for an individual game room.

  ## Responsibilities:
    * Dynamic, supervised process lifecycle registered via `Gameroom.Games.RoomRegistry`.
    * Game-agnostic room management (delegating moves, player turns, and status to game modules).
    * Player seating and spectator mode with role preferences and reconnect handling.
    * PubSub broadcasting for both room subscribers (`"room:<room_id>"`) and lobby subscribers (`"rooms:lobby"`).
    * Automatic room cleanup on idle timeout or when completely empty.
    * Rematch voting and game reset coordination.
  """

  use GenServer, restart: :temporary
  require Logger

  alias Gameroom.Games.RoomRegistry

  @default_idle_timeout_ms 30 * 60 * 1000
  @default_empty_timeout_ms 5 * 60 * 1000
  @default_pubsub Gameroom.PubSub
  @default_game_module Gameroom.Games.TicTacToe

  @type role :: atom()
  @type player_id :: String.t()
  @type room_status :: :waiting | :in_progress | :finished

  @type player :: %{
          player_id: player_id(),
          player_name: String.t(),
          role: role()
        }

  @type spectator :: %{
          player_id: player_id(),
          player_name: String.t()
        }

  @type t :: %__MODULE__{
          room_id: String.t(),
          game_module: module(),
          game_state: term(),
          seats: %{role() => player() | nil},
          spectators: %{player_id() => spectator()},
          status: room_status(),
          winner: role() | nil,
          finish_reason: :win | :draw | :forfeit | nil,
          pubsub: module() | atom(),
          idle_timeout_ms: non_neg_integer(),
          empty_timeout_ms: non_neg_integer(),
          idle_timer_ref: reference() | nil,
          empty_timer_ref: reference() | nil,
          rematch_votes: MapSet.t(player_id()),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :room_id,
    :game_module,
    :game_state,
    :seats,
    :spectators,
    :status,
    :winner,
    :finish_reason,
    :pubsub,
    :idle_timeout_ms,
    :empty_timeout_ms,
    :idle_timer_ref,
    :empty_timer_ref,
    :rematch_votes,
    :inserted_at,
    :updated_at
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a new game room GenServer.

  ## Options
    * `:room_id` - Unique room identifier (required)
    * `:game_module` - Game engine module (default `Gameroom.Games.TicTacToe`)
    * `:game_opts` - Options passed to `game_module.new_game/1` (default `[]`)
    * `:idle_timeout_ms` - Inactivity timeout in ms (default 30 mins)
    * `:empty_timeout_ms` - Empty room timeout in ms (default 5 mins)
    * `:pubsub` - Phoenix.PubSub server (default `Gameroom.PubSub`)
  """
  @spec start_link(keyword() | map()) :: GenServer.on_start()
  def start_link(opts) do
    opts_map = Map.new(opts)
    room_id = Map.fetch!(opts_map, :room_id)
    GenServer.start_link(__MODULE__, opts_map, name: via_tuple(room_id))
  end

  @doc """
  Returns the Registry `:via` tuple for the room identifier.
  """
  @spec via_tuple(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(room_id) when is_binary(room_id) do
    {:via, Registry, {RoomRegistry, room_id}}
  end

  @doc """
  Finds the PID of a room by room_id or returns the PID if already alive.
  """
  @spec whereis(String.t() | pid()) :: pid() | nil
  def whereis(pid) when is_pid(pid) do
    if Process.alive?(pid), do: pid, else: nil
  end

  def whereis(room_id) when is_binary(room_id) do
    GenServer.whereis(via_tuple(room_id))
  end

  def whereis(_), do: nil

  @doc """
  Retrieves the full state of the room.
  """
  @spec get_state(String.t() | pid(), timeout()) :: {:ok, t()} | {:error, term()}
  def get_state(room_id_or_pid, timeout \\ 5000) do
    call_room(room_id_or_pid, :get_state, timeout)
  end

  @doc """
  Retrieves a lightweight summary of the room suitable for lobby displays.
  """
  @spec get_summary(String.t() | pid(), timeout()) :: {:ok, map()} | {:error, term()}
  def get_summary(room_id_or_pid, timeout \\ 5000) do
    call_room(room_id_or_pid, :get_summary, timeout)
  end

  @doc """
  Joins a player to the room.

  If an open seat is available, the player is seated. If all seats are filled
  or if `:spectator` is requested, the player joins as a spectator. If the player
  was already in the room, their connection is preserved without duplicating seats.
  """
  @spec join(String.t() | pid(), player_id(), String.t(), role() | :spectator | nil, timeout()) ::
          {:ok, map()} | {:error, term()}
  def join(room_id_or_pid, player_id, player_name, requested_role \\ nil, timeout \\ 5000) do
    call_room(room_id_or_pid, {:join, player_id, player_name, requested_role}, timeout)
  end

  @doc """
  Removes a player or spectator from the room.
  """
  @spec leave(String.t() | pid(), player_id(), timeout()) :: {:ok, term()} | {:error, term()}
  def leave(room_id_or_pid, player_id, timeout \\ 5000) do
    call_room(room_id_or_pid, {:leave, player_id}, timeout)
  end

  @doc """
  Plays a move for the specified player.
  Validates player seating, turn order, and game rules via the game engine module.
  """
  @spec play_move(String.t() | pid(), player_id(), term(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def play_move(room_id_or_pid, player_id, move, timeout \\ 5000) do
    normalized_move = normalize_move(move)
    call_room(room_id_or_pid, {:play_move, player_id, normalized_move}, timeout)
  end

  @doc """
  Votes for a rematch once a game has finished.
  When all seated players have voted, a new game begins.
  """
  @spec rematch(String.t() | pid(), player_id(), timeout()) ::
          {:ok, :rematch_requested | :rematch_started} | {:error, term()}
  def rematch(room_id_or_pid, player_id, timeout \\ 5000) do
    call_room(room_id_or_pid, {:rematch, player_id}, timeout)
  end

  @doc """
  Resets the game state immediately (preserving seated players).
  """
  @spec reset_game(String.t() | pid(), keyword(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def reset_game(room_id_or_pid, opts \\ [], timeout \\ 5000) do
    call_room(room_id_or_pid, {:reset_game, opts}, timeout)
  end

  @doc """
  Promotes a spectator into an open player seat.
  """
  @spec take_seat(String.t() | pid(), player_id(), role() | nil, timeout()) ::
          {:ok, role()} | {:error, term()}
  def take_seat(room_id_or_pid, player_id, requested_role \\ nil, timeout \\ 5000) do
    call_room(room_id_or_pid, {:take_seat, player_id, requested_role}, timeout)
  end

  @doc """
  Switches a seated player to spectator mode (allowed when waiting or finished).
  """
  @spec switch_to_spectator(String.t() | pid(), player_id(), timeout()) ::
          {:ok, :spectator} | {:error, term()}
  def switch_to_spectator(room_id_or_pid, player_id, timeout \\ 5000) do
    call_room(room_id_or_pid, {:switch_to_spectator, player_id}, timeout)
  end

  @doc """
  Forfeits the game for a seated player.
  """
  @spec forfeit(String.t() | pid(), player_id(), timeout()) ::
          {:ok, role()} | {:error, term()}
  def forfeit(room_id_or_pid, player_id, timeout \\ 5000) do
    call_room(room_id_or_pid, {:forfeit, player_id}, timeout)
  end

  @doc """
  Stops the room process gracefully.
  """
  @spec stop(String.t() | pid(), term(), timeout()) :: :ok | {:error, term()}
  def stop(room_id_or_pid, reason \\ :normal, timeout \\ 5000) do
    call_room(room_id_or_pid, {:stop, reason}, timeout)
  end

  @doc """
  Returns whose turn it is currently, or `nil` if the game is waiting or finished.
  Delegates turn queries to the underlying game module.
  """
  @spec current_player(t()) :: role() | nil
  def current_player(%__MODULE__{status: :in_progress, game_module: mod, game_state: gs}) do
    mod.current_player(gs)
  end

  def current_player(%__MODULE__{}), do: nil

  @doc """
  Returns the role of a given player in the room (`:spectator`, a seat role atom, or `nil`).
  """
  @spec role_for(t(), player_id()) :: role() | :spectator | nil
  def role_for(%__MODULE__{} = room, player_id) do
    role_for_player(room, player_id)
  end

  @doc """
  Returns true if the player is seated in a playing seat.
  """
  @spec seated?(t(), player_id()) :: boolean()
  def seated?(%__MODULE__{} = room, player_id) do
    case role_for_player(room, player_id) do
      nil -> false
      :spectator -> false
      _role -> true
    end
  end

  @doc """
  Returns true if the player is in the spectator list.
  """
  @spec spectator?(t(), player_id()) :: boolean()
  def spectator?(%__MODULE__{spectators: spectators}, player_id) do
    Map.has_key?(spectators, player_id)
  end

  @doc """
  Returns true if the player is either seated or spectating.
  """
  @spec in_room?(t(), player_id()) :: boolean()
  def in_room?(%__MODULE__{} = room, player_id) do
    role_for_player(room, player_id) != nil
  end

  @doc """
  Builds a summary map suitable for lobby listings and quick metadata inspection.
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = room) do
    roles = room.game_module.player_roles()
    seated_count = Enum.count(roles, fn r -> Map.get(room.seats, r) != nil end)
    spectator_count = map_size(room.spectators)

    current_player_role =
      if room.status == :in_progress do
        room.game_module.current_player(room.game_state)
      else
        nil
      end

    winner =
      cond do
        room.status != :finished ->
          nil

        room.winner != nil ->
          room.winner

        function_exported?(room.game_module, :winner, 1) ->
          room.game_module.winner(room.game_state)

        true ->
          case room.game_module.game_status(room.game_state) do
            {:winner, w} -> w
            _ -> nil
          end
      end

    winning_line =
      if room.status == :finished do
        Map.get(room.game_state, :winning_line)
      else
        nil
      end

    %{
      room_id: room.room_id,
      game_module: room.game_module,
      status: room.status,
      player_count: seated_count,
      max_players: length(roles),
      seats:
        Map.new(roles, fn r ->
          player = Map.get(room.seats, r)
          {r, (player && player.player_name) || nil}
        end),
      seats_detail: room.seats,
      spectator_count: spectator_count,
      current_player: current_player_role,
      winner: winner,
      finish_reason: room.finish_reason,
      winning_line: winning_line,
      inserted_at: room.inserted_at,
      updated_at: room.updated_at
    }
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    room_id = Map.fetch!(opts, :room_id)
    game_module = Map.get(opts, :game_module, @default_game_module)
    game_opts = Map.get(opts, :game_opts, [])
    pubsub = Map.get(opts, :pubsub, @default_pubsub)
    idle_timeout_ms = Map.get(opts, :idle_timeout_ms, @default_idle_timeout_ms)
    empty_timeout_ms = Map.get(opts, :empty_timeout_ms, @default_empty_timeout_ms)

    roles = game_module.player_roles()
    seats = Map.new(roles, fn r -> {r, nil} end)
    game_state = game_module.new_game(game_opts)
    now = DateTime.utc_now()

    state = %__MODULE__{
      room_id: room_id,
      game_module: game_module,
      game_state: game_state,
      seats: seats,
      spectators: %{},
      status: :waiting,
      winner: nil,
      finish_reason: nil,
      pubsub: pubsub,
      idle_timeout_ms: idle_timeout_ms,
      empty_timeout_ms: empty_timeout_ms,
      rematch_votes: MapSet.new(),
      inserted_at: now,
      updated_at: now
    }

    state = schedule_idle_timer(state)
    state = schedule_empty_timer_if_needed(state)

    room_summary = summary(state)
    Registry.update_value(RoomRegistry, room_id, fn _ -> room_summary end)
    Phoenix.PubSub.broadcast(pubsub, "rooms:lobby", {:room_created, room_summary})

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_summary, _from, state) do
    {:reply, {:ok, summary(state)}, state}
  end

  def handle_call({:join, player_id, player_name, requested_role}, _from, state) do
    # 1. Check if player is already seated
    existing_seat = Enum.find(state.seats, fn {_r, p} -> p && p.player_id == player_id end)

    if existing_seat do
      {role, current_info} = existing_seat
      updated_player = %{current_info | player_name: player_name}
      new_seats = Map.put(state.seats, role, updated_player)
      state = %{state | seats: new_seats, updated_at: DateTime.utc_now()}
      state = reset_activity(state)

      payload = %{
        room_id: state.room_id,
        player_id: player_id,
        player_name: player_name,
        role: role,
        spectator: false,
        rejoined: true,
        status: state.status,
        summary: summary(state),
        state: state
      }

      broadcast_room(state, :player_joined, payload)
      sync_registry_and_broadcast_lobby(state)
      {:reply, {:ok, %{role: role, spectator: false, rejoined: true}}, state}
    else
      # 2. Check if player is already in spectators
      if Map.has_key?(state.spectators, player_id) do
        updated_spectators =
          Map.put(state.spectators, player_id, %{
            player_id: player_id,
            player_name: player_name
          })

        state = %{state | spectators: updated_spectators, updated_at: DateTime.utc_now()}
        state = reset_activity(state)

        payload = %{
          room_id: state.room_id,
          player_id: player_id,
          player_name: player_name,
          role: :spectator,
          spectator: true,
          rejoined: true,
          status: state.status,
          summary: summary(state),
          state: state
        }

        broadcast_room(state, :player_joined, payload)
        sync_registry_and_broadcast_lobby(state)
        {:reply, {:ok, %{role: :spectator, spectator: true, rejoined: true}}, state}
      else
        # 3. New participant joining
        roles = state.game_module.player_roles()
        normalized_role = normalize_requested_role(requested_role, roles)

        if requested_role in [:spectator, "spectator"] do
          # Explicit spectator request
          join_as_spectator(state, player_id, player_name)
        else
          # Try to assign a seat
          assigned_role =
            if normalized_role && Map.get(state.seats, normalized_role) == nil do
              normalized_role
            else
              Enum.find(roles, fn r -> Map.get(state.seats, r) == nil end)
            end

          if assigned_role do
            join_as_player(state, player_id, player_name, assigned_role)
          else
            # Seats full -> fall back to spectator
            join_as_spectator(state, player_id, player_name)
          end
        end
      end
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    cond do
      Map.has_key?(state.spectators, player_id) ->
        new_spectators = Map.delete(state.spectators, player_id)
        state = %{state | spectators: new_spectators, updated_at: DateTime.utc_now()}
        state = schedule_empty_timer_if_needed(state)

        payload = %{
          room_id: state.room_id,
          player_id: player_id,
          role: :spectator,
          spectator: true,
          summary: summary(state),
          state: state
        }

        broadcast_room(state, :player_left, payload)
        sync_registry_and_broadcast_lobby(state)
        {:reply, {:ok, :left}, state}

      seated_seat = Enum.find(state.seats, fn {_r, p} -> p && p.player_id == player_id end) ->
        {role, _p} = seated_seat

        case state.status do
          :waiting ->
            new_seats = Map.put(state.seats, role, nil)
            state = %{state | seats: new_seats, updated_at: DateTime.utc_now()}
            state = schedule_empty_timer_if_needed(state)

            payload = %{
              room_id: state.room_id,
              player_id: player_id,
              role: role,
              spectator: false,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :player_left, payload)
            sync_registry_and_broadcast_lobby(state)
            {:reply, {:ok, :left}, state}

          :in_progress ->
            # Mid-game leave: award win to remaining player if 2-player game
            other_role = Enum.find(state.game_module.player_roles(), fn r -> r != role end)
            new_seats = Map.put(state.seats, role, nil)
            new_status = :finished

            state = %{
              state
              | seats: new_seats,
                status: new_status,
                winner: other_role,
                finish_reason: :forfeit,
                rematch_votes: MapSet.new(),
                updated_at: DateTime.utc_now()
            }

            state = schedule_empty_timer_if_needed(state)

            payload_left = %{
              room_id: state.room_id,
              player_id: player_id,
              role: role,
              spectator: false,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :player_left, payload_left)

            payload_over = %{
              room_id: state.room_id,
              status: {:winner, other_role},
              winner: other_role,
              finish_reason: :forfeit,
              reason: :forfeit,
              forfeited_by: player_id,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :game_over, payload_over)
            sync_registry_and_broadcast_lobby(state)
            {:reply, {:ok, :forfeit}, state}

          :finished ->
            new_seats = Map.put(state.seats, role, nil)

            state = %{
              state
              | seats: new_seats,
                rematch_votes: MapSet.delete(state.rematch_votes, player_id),
                updated_at: DateTime.utc_now()
            }

            state = schedule_empty_timer_if_needed(state)

            payload = %{
              room_id: state.room_id,
              player_id: player_id,
              role: role,
              spectator: false,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :player_left, payload)
            sync_registry_and_broadcast_lobby(state)
            {:reply, {:ok, :left}, state}
        end

      true ->
        {:reply, {:error, :not_in_room}, state}
    end
  end

  def handle_call({:play_move, player_id, move}, _from, state) do
    role = role_for_player(state, player_id)

    cond do
      role == nil or role == :spectator ->
        {:reply, {:error, :not_a_player}, state}

      state.status == :waiting ->
        {:reply, {:error, :waiting_for_players}, state}

      state.status == :finished ->
        {:reply, {:error, :game_over}, state}

      role != state.game_module.current_player(state.game_state) ->
        {:reply, {:error, :not_player_turn}, state}

      true ->
        case state.game_module.apply_move(state.game_state, role, move) do
          {:ok, new_game_state} ->
            game_status = state.game_module.game_status(new_game_state)

            new_room_status =
              if game_status == :in_progress, do: :in_progress, else: :finished

            state = %{
              state
              | game_state: new_game_state,
                status: new_room_status,
                updated_at: DateTime.utc_now()
            }

            state = schedule_idle_timer(state)

            next_turn = state.game_module.current_player(new_game_state)

            move_payload = %{
              room_id: state.room_id,
              player_id: player_id,
              role: role,
              move: move,
              game_state: new_game_state,
              current_player: next_turn,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :move_played, move_payload)

            if new_room_status == :finished do
              winner =
                if function_exported?(state.game_module, :winner, 1) do
                  state.game_module.winner(new_game_state)
                else
                  case game_status do
                    {:winner, w} -> w
                    _ -> nil
                  end
                end

              finish_reason = if winner, do: :win, else: :draw
              winning_line = Map.get(new_game_state, :winning_line)

              state = %{state | winner: winner, finish_reason: finish_reason}

              over_payload = %{
                room_id: state.room_id,
                status: game_status,
                winner: winner,
                finish_reason: finish_reason,
                winning_line: winning_line,
                summary: summary(state),
                state: state
              }

              broadcast_room(state, :game_over, over_payload)
              sync_registry_and_broadcast_lobby(state)
              {:reply, {:ok, new_game_state}, state}
            else
              sync_registry_and_broadcast_lobby(state)
              {:reply, {:ok, new_game_state}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:rematch, player_id}, _from, state) do
    if state.status != :finished do
      {:reply, {:error, :game_not_finished}, state}
    else
      role = role_for_player(state, player_id)

      if role == nil or role == :spectator do
        {:reply, {:error, :not_a_seated_player}, state}
      else
        roles = state.game_module.player_roles()
        all_seated? = Enum.all?(roles, fn r -> Map.get(state.seats, r) != nil end)

        if not all_seated? do
          {:reply, {:error, :waiting_for_players}, state}
        else
          new_votes = MapSet.put(state.rematch_votes, player_id)
          seated_ids = for {_r, p} <- state.seats, p != nil, do: p.player_id
          all_voted? = Enum.all?(seated_ids, fn id -> MapSet.member?(new_votes, id) end)

          if all_voted? do
            new_game_state = state.game_module.new_game()

            state = %{
              state
              | game_state: new_game_state,
                status: :in_progress,
                winner: nil,
                finish_reason: nil,
                rematch_votes: MapSet.new(),
                updated_at: DateTime.utc_now()
            }

            state = schedule_idle_timer(state)
            current_turn = state.game_module.current_player(new_game_state)

            reset_payload = %{
              room_id: state.room_id,
              game_state: new_game_state,
              current_player: current_turn,
              summary: summary(state),
              state: state
            }

            broadcast_room(state, :game_reset, reset_payload)
            sync_registry_and_broadcast_lobby(state)
            {:reply, {:ok, :rematch_started}, state}
          else
            state = %{state | rematch_votes: new_votes, updated_at: DateTime.utc_now()}

            req_payload = %{
              room_id: state.room_id,
              player_id: player_id,
              role: role,
              votes: MapSet.to_list(new_votes),
              required: length(seated_ids)
            }

            broadcast_room(state, :rematch_requested, req_payload)
            {:reply, {:ok, :rematch_requested}, state}
          end
        end
      end
    end
  end

  def handle_call({:reset_game, opts}, _from, state) do
    new_game_state = state.game_module.new_game(opts)
    roles = state.game_module.player_roles()
    all_seated? = Enum.all?(roles, fn r -> Map.get(state.seats, r) != nil end)
    new_status = if all_seated?, do: :in_progress, else: :waiting

    state = %{
      state
      | game_state: new_game_state,
        status: new_status,
        winner: nil,
        finish_reason: nil,
        rematch_votes: MapSet.new(),
        updated_at: DateTime.utc_now()
    }

    state = schedule_idle_timer(state)
    current_turn = state.game_module.current_player(new_game_state)

    payload = %{
      room_id: state.room_id,
      game_state: new_game_state,
      current_player: current_turn,
      summary: summary(state),
      state: state
    }

    broadcast_room(state, :game_reset, payload)
    sync_registry_and_broadcast_lobby(state)
    {:reply, {:ok, new_game_state}, state}
  end

  def handle_call({:take_seat, player_id, requested_role}, _from, state) do
    if state.status == :in_progress do
      {:reply, {:error, :game_in_progress}, state}
    else
      case Map.get(state.spectators, player_id) do
        nil ->
          {:reply, {:error, :not_a_spectator}, state}

        spectator ->
          roles = state.game_module.player_roles()
          normalized_role = normalize_requested_role(requested_role, roles)

          cond do
            requested_role != nil and normalized_role == nil ->
              {:reply, {:error, :invalid_role}, state}

            requested_role != nil and Map.get(state.seats, normalized_role) != nil ->
              {:reply, {:error, :seat_taken}, state}

            true ->
              target_role =
                if normalized_role do
                  normalized_role
                else
                  Enum.find(roles, fn r -> Map.get(state.seats, r) == nil end)
                end

              if target_role do
                new_player = %{
                  player_id: player_id,
                  player_name: spectator.player_name,
                  role: target_role
                }

                new_seats = Map.put(state.seats, target_role, new_player)
                new_spectators = Map.delete(state.spectators, player_id)
                all_seated? = Enum.all?(roles, fn r -> Map.get(new_seats, r) != nil end)

                new_status =
                  if all_seated? and state.status == :waiting,
                    do: :in_progress,
                    else: state.status

                state = %{
                  state
                  | seats: new_seats,
                    spectators: new_spectators,
                    status: new_status,
                    updated_at: DateTime.utc_now()
                }

                state = reset_activity(state)

                payload = %{
                  room_id: state.room_id,
                  player_id: player_id,
                  role: target_role,
                  summary: summary(state),
                  state: state
                }

                broadcast_room(state, :player_switched_role, payload)
                sync_registry_and_broadcast_lobby(state)
                {:reply, {:ok, target_role}, state}
              else
                {:reply, {:error, :no_seats_available}, state}
              end
          end
      end
    end
  end

  def handle_call({:switch_to_spectator, player_id}, _from, state) do
    if state.status == :in_progress do
      {:reply, {:error, :game_in_progress}, state}
    else
      case Enum.find(state.seats, fn {_r, p} -> p && p.player_id == player_id end) do
        {role, player} ->
          new_seats = Map.put(state.seats, role, nil)

          new_spectators =
            Map.put(state.spectators, player_id, %{
              player_id: player_id,
              player_name: player.player_name
            })

          new_status = if state.status == :waiting, do: :waiting, else: state.status

          state = %{
            state
            | seats: new_seats,
              spectators: new_spectators,
              status: new_status,
              rematch_votes: MapSet.delete(state.rematch_votes, player_id),
              updated_at: DateTime.utc_now()
          }

          state = reset_activity(state)

          payload = %{
            room_id: state.room_id,
            player_id: player_id,
            from: role,
            to: :spectator,
            summary: summary(state),
            state: state
          }

          broadcast_room(state, :player_switched_role, payload)
          sync_registry_and_broadcast_lobby(state)
          {:reply, {:ok, :spectator}, state}

        nil ->
          {:reply, {:error, :not_a_seated_player}, state}
      end
    end
  end

  def handle_call({:forfeit, player_id}, _from, state) do
    if state.status != :in_progress do
      {:reply, {:error, :cannot_forfeit}, state}
    else
      case Enum.find(state.seats, fn {_r, p} -> p && p.player_id == player_id end) do
        {role, _p} ->
          other_role = Enum.find(state.game_module.player_roles(), fn r -> r != role end)
          new_status = :finished

          state = %{
            state
            | status: new_status,
              winner: other_role,
              finish_reason: :forfeit,
              rematch_votes: MapSet.new(),
              updated_at: DateTime.utc_now()
          }

          payload = %{
            room_id: state.room_id,
            status: {:winner, other_role},
            winner: other_role,
            finish_reason: :forfeit,
            reason: :forfeit,
            forfeited_by: player_id,
            summary: summary(state),
            state: state
          }

          broadcast_room(state, :game_over, payload)
          sync_registry_and_broadcast_lobby(state)
          {:reply, {:ok, other_role}, state}

        nil ->
          {:reply, {:error, :not_a_seated_player}, state}
      end
    end
  end

  def handle_call({:stop, reason}, _from, state) do
    {:stop, reason, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # GenServer Info & Termination Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:idle_timeout, state) do
    Logger.info("[Gameroom.Games.Room] Room #{state.room_id} stopped due to idle inactivity")
    {:stop, {:shutdown, :idle_timeout}, state}
  end

  def handle_info(:empty_timeout, state) do
    Logger.info("[Gameroom.Games.Room] Room #{state.room_id} stopped because it was empty")
    {:stop, {:shutdown, :empty_timeout}, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    if state.idle_timer_ref, do: Process.cancel_timer(state.idle_timer_ref)
    if state.empty_timer_ref, do: Process.cancel_timer(state.empty_timer_ref)

    exit_reason =
      case reason do
        {:shutdown, r} -> r
        r -> r
      end

    Phoenix.PubSub.broadcast(
      state.pubsub,
      "rooms:lobby",
      {:room_deleted, %{room_id: state.room_id}}
    )

    broadcast_room_closed(state, exit_reason)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp call_room(room_id_or_pid, message, timeout) do
    case whereis(room_id_or_pid) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(pid, message, timeout)
        catch
          :exit, {:noproc, _} -> {:error, :not_found}
          :exit, {:timeout, _} -> {:error, :timeout}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp join_as_player(state, player_id, player_name, role) do
    new_player = %{player_id: player_id, player_name: player_name, role: role}
    new_seats = Map.put(state.seats, role, new_player)
    roles = state.game_module.player_roles()
    all_seated? = Enum.all?(roles, fn r -> Map.get(new_seats, r) != nil end)

    new_status =
      if all_seated? and state.status == :waiting, do: :in_progress, else: state.status

    state = %{
      state
      | seats: new_seats,
        status: new_status,
        updated_at: DateTime.utc_now()
    }

    state = reset_activity(state)

    payload = %{
      room_id: state.room_id,
      player_id: player_id,
      player_name: player_name,
      role: role,
      spectator: false,
      rejoined: false,
      status: new_status,
      summary: summary(state),
      state: state
    }

    broadcast_room(state, :player_joined, payload)
    sync_registry_and_broadcast_lobby(state)
    {:reply, {:ok, %{role: role, spectator: false, rejoined: false}}, state}
  end

  defp join_as_spectator(state, player_id, player_name) do
    new_spectator = %{player_id: player_id, player_name: player_name}
    new_spectators = Map.put(state.spectators, player_id, new_spectator)
    state = %{state | spectators: new_spectators, updated_at: DateTime.utc_now()}
    state = reset_activity(state)

    payload = %{
      room_id: state.room_id,
      player_id: player_id,
      player_name: player_name,
      role: :spectator,
      spectator: true,
      rejoined: false,
      summary: summary(state),
      state: state
    }

    broadcast_room(state, :player_joined, payload)
    sync_registry_and_broadcast_lobby(state)
    {:reply, {:ok, %{role: :spectator, spectator: true, rejoined: false}}, state}
  end

  defp role_for_player(%__MODULE__{seats: seats, spectators: spectators}, player_id) do
    case Enum.find(seats, fn {_r, p} -> p && p.player_id == player_id end) do
      {role, _p} -> role
      nil -> if Map.has_key?(spectators, player_id), do: :spectator, else: nil
    end
  end

  defp player_count(%__MODULE__{seats: seats, spectators: spectators, game_module: game_module}) do
    seated_count = Enum.count(game_module.player_roles(), fn r -> Map.get(seats, r) != nil end)
    seated_count + map_size(spectators)
  end

  defp reset_activity(state) do
    state
    |> schedule_idle_timer()
    |> cancel_empty_timer()
  end

  defp schedule_idle_timer(%__MODULE__{idle_timeout_ms: ms} = state) when ms > 0 do
    if state.idle_timer_ref, do: Process.cancel_timer(state.idle_timer_ref)
    ref = Process.send_after(self(), :idle_timeout, ms)
    %{state | idle_timer_ref: ref}
  end

  defp schedule_idle_timer(state), do: %{state | idle_timer_ref: nil}

  defp schedule_empty_timer(%__MODULE__{empty_timeout_ms: ms} = state) when ms > 0 do
    if state.empty_timer_ref == nil do
      ref = Process.send_after(self(), :empty_timeout, ms)
      %{state | empty_timer_ref: ref}
    else
      state
    end
  end

  defp schedule_empty_timer(state), do: %{state | empty_timer_ref: nil}

  defp cancel_empty_timer(%__MODULE__{} = state) do
    if state.empty_timer_ref do
      Process.cancel_timer(state.empty_timer_ref)
      %{state | empty_timer_ref: nil}
    else
      state
    end
  end

  defp schedule_empty_timer_if_needed(%__MODULE__{} = state) do
    if player_count(state) == 0 do
      schedule_empty_timer(state)
    else
      cancel_empty_timer(state)
    end
  end

  defp sync_registry_and_broadcast_lobby(%__MODULE__{} = state) do
    room_summary = summary(state)
    Registry.update_value(RoomRegistry, state.room_id, fn _ -> room_summary end)
    Phoenix.PubSub.broadcast(state.pubsub, "rooms:lobby", {:room_updated, room_summary})
  end

  defp broadcast_room(%__MODULE__{} = state, event, payload) do
    Phoenix.PubSub.broadcast(state.pubsub, "room:#{state.room_id}", {event, payload})
  end

  defp broadcast_room_closed(%__MODULE__{} = state, reason) do
    Phoenix.PubSub.broadcast(
      state.pubsub,
      "room:#{state.room_id}",
      {:room_closed, %{room_id: state.room_id, reason: reason}}
    )
  end

  defp normalize_requested_role(nil, _valid_roles), do: nil

  defp normalize_requested_role(role, valid_roles) when is_atom(role) do
    if role in valid_roles, do: role, else: nil
  end

  defp normalize_requested_role(role_str, valid_roles) when is_binary(role_str) do
    Enum.find(valid_roles, fn r -> Atom.to_string(r) == role_str end)
  end

  defp normalize_requested_role(_other, _valid_roles), do: nil

  defp normalize_move(val) when is_binary(val) do
    case Integer.parse(val) do
      {idx, ""} -> idx
      _ -> val
    end
  end

  defp normalize_move(val), do: val
end
