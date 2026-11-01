defmodule Gameroom.Games.RoomTest do
  use ExUnit.Case, async: false

  alias Gameroom.Games.Room
  alias Gameroom.Games.RoomSupervisor

  setup do
    room_id = "test-room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      RoomSupervisor.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  defp start_room(room_id, opts \\ []) do
    opts = Keyword.merge([room_id: room_id], opts)
    {:ok, pid} = RoomSupervisor.start_room(opts)
    pid
  end

  describe "initialization and state" do
    test "initializes with waiting status and empty seats", %{room_id: room_id} do
      start_room(room_id)
      assert {:ok, state} = Room.get_state(room_id)

      assert state.room_id == room_id
      assert state.status == :waiting
      assert state.seats == %{x: nil, o: nil}
      assert state.spectators == %{}
      assert state.winner == nil
      assert state.finish_reason == nil
      assert Room.current_player(state) == nil
    end

    test "summary returns metadata formatted for client & lobby", %{room_id: room_id} do
      start_room(room_id)
      assert {:ok, summary} = Room.get_summary(room_id)

      assert summary.room_id == room_id
      assert summary.status == :waiting
      assert summary.player_count == 0
      assert summary.max_players == 2
      assert summary.spectator_count == 0
      assert summary.current_player == nil
      assert summary.winner == nil
      assert summary.finish_reason == nil
    end
  end

  describe "player seating and spectator management" do
    test "first two players take seats, third becomes spectator", %{room_id: room_id} do
      start_room(room_id)

      # Player 1 joins -> seat :x, room remains :waiting
      assert {:ok, res1} = Room.join(room_id, "p1", "Alice")
      assert res1.role == :x
      assert res1.spectator == false
      assert res1.rejoined == false

      {:ok, state1} = Room.get_state(room_id)
      assert state1.status == :waiting
      assert Room.role_for(state1, "p1") == :x
      assert Room.seated?(state1, "p1")
      refute Room.spectator?(state1, "p1")
      assert Room.in_room?(state1, "p1")

      # Player 2 joins -> seat :o, room transitions to :in_progress
      assert {:ok, res2} = Room.join(room_id, "p2", "Bob")
      assert res2.role == :o
      assert res2.spectator == false

      {:ok, state2} = Room.get_state(room_id)
      assert state2.status == :in_progress
      assert Room.current_player(state2) == :x

      # Player 3 joins -> all seats taken, joins as spectator
      assert {:ok, res3} = Room.join(room_id, "p3", "Charlie")
      assert res3.role == :spectator
      assert res3.spectator == true

      {:ok, state3} = Room.get_state(room_id)
      assert Room.role_for(state3, "p3") == :spectator
      refute Room.seated?(state3, "p3")
      assert Room.spectator?(state3, "p3")
    end

    test "joining explicitly as spectator", %{room_id: room_id} do
      start_room(room_id)

      assert {:ok, res} = Room.join(room_id, "p1", "Alice", :spectator)
      assert res.role == :spectator
      assert res.spectator == true

      {:ok, state} = Room.get_state(room_id)
      assert state.status == :waiting
      assert state.seats == %{x: nil, o: nil}
      assert Map.has_key?(state.spectators, "p1")
    end

    test "rejoining preserves player seat and updates nickname", %{room_id: room_id} do
      start_room(room_id)
      assert {:ok, _} = Room.join(room_id, "p1", "Alice")

      assert {:ok, rejoin} = Room.join(room_id, "p1", "Alice Updated")
      assert rejoin.role == :x
      assert rejoin.rejoined == true

      {:ok, state} = Room.get_state(room_id)
      assert state.seats.x.player_name == "Alice Updated"
    end

    test "rejoining as spectator preserves spectator status and updates nickname", %{
      room_id: room_id
    } do
      start_room(room_id)
      assert {:ok, _} = Room.join(room_id, "p1", "Alice", :spectator)

      assert {:ok, rejoin} = Room.join(room_id, "p1", "Alice Renamed", :spectator)
      assert rejoin.role == :spectator
      assert rejoin.rejoined == true

      {:ok, state} = Room.get_state(room_id)
      assert state.spectators["p1"].player_name == "Alice Renamed"
    end

    test "spectator can take an open seat when waiting", %{room_id: room_id} do
      start_room(room_id)
      assert {:ok, _} = Room.join(room_id, "p1", "Alice", :spectator)

      assert {:ok, :x} = Room.take_seat(room_id, "p1", :x)

      {:ok, state} = Room.get_state(room_id)
      assert state.seats.x.player_name == "Alice"
      refute Map.has_key?(state.spectators, "p1")
    end

    test "take_seat errors when game is in progress, seat is taken, or invalid", %{
      room_id: room_id
    } do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")
      Room.join(room_id, "p3", "Charlie")

      # Game is in progress
      assert Room.take_seat(room_id, "p3", :x) == {:error, :game_in_progress}

      # Non-spectator error
      assert Room.take_seat(room_id, "unknown", :x) == {:error, :game_in_progress}
    end

    test "take_seat validation when room is waiting", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice", :x)
      Room.join(room_id, "p2", "Bob", :spectator)

      # Seat X is already taken
      assert Room.take_seat(room_id, "p2", :x) == {:error, :seat_taken}

      # Invalid role
      assert Room.take_seat(room_id, "p2", :invalid_role) == {:error, :invalid_role}

      # Non-spectator
      assert Room.take_seat(room_id, "not_in_room", :o) == {:error, :not_a_spectator}

      # Take open seat O succeeds and starts game
      assert Room.take_seat(room_id, "p2", :o) == {:ok, :o}
      {:ok, state} = Room.get_state(room_id)
      assert state.status == :in_progress
    end

    test "seated player can switch to spectator when waiting or finished", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")

      assert {:ok, :spectator} = Room.switch_to_spectator(room_id, "p1")
      {:ok, state} = Room.get_state(room_id)
      assert state.seats.x == nil
      assert Map.has_key?(state.spectators, "p1")
    end

    test "switch_to_spectator rejected during active match", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      assert Room.switch_to_spectator(room_id, "p1") == {:error, :game_in_progress}
    end
  end

  describe "gameplay and move validation" do
    test "alternates turns and finishes on winning condition", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      # Alice (X) plays top row: 0
      assert {:ok, _} = Room.play_move(room_id, "p1", 0)
      {:ok, state} = Room.get_state(room_id)
      assert Room.current_player(state) == :o

      # Bob (O) tries to play Alice's cell -> error
      assert Room.play_move(room_id, "p2", 0) == {:error, :cell_occupied}

      # Bob plays middle row: 3
      assert {:ok, _} = Room.play_move(room_id, "p2", 3)

      # Alice plays 1
      assert {:ok, _} = Room.play_move(room_id, "p1", 1)

      # Bob plays 4
      assert {:ok, _} = Room.play_move(room_id, "p2", 4)

      # Alice plays 2 -> winning horizontal line [0, 1, 2]
      assert {:ok, final_gs} = Room.play_move(room_id, "p1", 2)
      assert final_gs.status == {:winner, :x}

      {:ok, room_state} = Room.get_state(room_id)
      assert room_state.status == :finished
      assert room_state.winner == :x
      assert room_state.finish_reason == :win
      assert Room.current_player(room_state) == nil

      {:ok, summary} = Room.get_summary(room_id)
      assert summary.status == :finished
      assert summary.winner == :x
      assert summary.finish_reason == :win
      assert summary.winning_line == [{0, 0}, {0, 1}, {0, 2}]

      # Moves after game over are rejected
      assert Room.play_move(room_id, "p2", 5) == {:error, :game_over}
    end

    test "rejects move when out of turn, spectator, or waiting", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")

      # Waiting for players
      assert Room.play_move(room_id, "p1", 0) == {:error, :waiting_for_players}

      Room.join(room_id, "p2", "Bob")
      Room.join(room_id, "p3", "Charlie")

      # Spectator move
      assert Room.play_move(room_id, "p3", 0) == {:error, :not_a_player}

      # Bob's turn out of order
      assert Room.play_move(room_id, "p2", 0) == {:error, :not_player_turn}
    end

    test "ends in draw when all cells filled without winner", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      # Moves leading to draw:
      # X: 0, 2, 3, 7, 8
      # O: 1, 4, 5, 6
      Room.play_move(room_id, "p1", 0)
      Room.play_move(room_id, "p2", 1)
      Room.play_move(room_id, "p1", 2)
      Room.play_move(room_id, "p2", 4)
      Room.play_move(room_id, "p1", 3)
      Room.play_move(room_id, "p2", 5)
      Room.play_move(room_id, "p1", 7)
      Room.play_move(room_id, "p2", 6)
      assert {:ok, _} = Room.play_move(room_id, "p1", 8)

      {:ok, state} = Room.get_state(room_id)
      assert state.status == :finished
      assert state.winner == nil
      assert state.finish_reason == :draw

      {:ok, summary} = Room.get_summary(room_id)
      assert summary.status == :finished
      assert summary.winner == nil
      assert summary.finish_reason == :draw
      assert summary.winning_line == nil
    end
  end

  describe "forfeits and player leaves" do
    test "explicit forfeit mid-game awards win to opponent", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      assert {:ok, :o} = Room.forfeit(room_id, "p1")

      {:ok, state} = Room.get_state(room_id)
      assert state.status == :finished
      assert state.winner == :o
      assert state.finish_reason == :forfeit

      {:ok, summary} = Room.get_summary(room_id)
      assert summary.status == :finished
      assert summary.winner == :o
      assert summary.finish_reason == :forfeit
    end

    test "leaving mid-game causes forfeit and awards win to remaining player", %{
      room_id: room_id
    } do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      assert {:ok, :forfeit} = Room.leave(room_id, "p1")

      {:ok, state} = Room.get_state(room_id)
      assert state.status == :finished
      assert state.winner == :o
      assert state.finish_reason == :forfeit
      assert state.seats.x == nil
      assert state.seats.o.player_name == "Bob"
    end

    test "spectator leaving does not affect game status", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")
      Room.join(room_id, "p3", "Charlie")

      assert {:ok, :left} = Room.leave(room_id, "p3")

      {:ok, state} = Room.get_state(room_id)
      assert state.status == :in_progress
      refute Map.has_key?(state.spectators, "p3")
    end
  end

  describe "rematch and game reset" do
    test "rematch requires all seated players to vote", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      # Forfeit to finish quickly
      Room.forfeit(room_id, "p1")

      # First player votes rematch
      assert {:ok, :rematch_requested} = Room.rematch(room_id, "p1")
      {:ok, state} = Room.get_state(room_id)
      assert MapSet.member?(state.rematch_votes, "p1")
      assert state.status == :finished

      # Second player votes rematch -> starts new match
      assert {:ok, :rematch_started} = Room.rematch(room_id, "p2")
      {:ok, new_state} = Room.get_state(room_id)
      assert new_state.status == :in_progress
      assert new_state.winner == nil
      assert new_state.finish_reason == nil
      assert Room.current_player(new_state) == :x
    end

    test "rematch blocked if game is not finished or players missing", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")

      # Match still in progress
      assert Room.rematch(room_id, "p1") == {:error, :game_not_finished}

      # Player leaves mid-game (resulting in finished state with only 1 player seated)
      Room.leave(room_id, "p2")
      assert Room.rematch(room_id, "p1") == {:error, :waiting_for_players}
    end

    test "reset_game restarts immediately", %{room_id: room_id} do
      start_room(room_id)
      Room.join(room_id, "p1", "Alice")
      Room.join(room_id, "p2", "Bob")
      Room.play_move(room_id, "p1", 0)

      assert {:ok, _} = Room.reset_game(room_id)
      {:ok, state} = Room.get_state(room_id)
      assert state.status == :in_progress
      assert Room.current_player(state) == :x
      assert state.game_state.moves_count == 0
    end
  end

  describe "pubsub broadcasting" do
    test "broadcasts room events to room topic and updates to lobby topic", %{room_id: room_id} do
      # Subscribe to room and lobby
      Phoenix.PubSub.subscribe(Gameroom.PubSub, "room:#{room_id}")
      Phoenix.PubSub.subscribe(Gameroom.PubSub, "rooms:lobby")

      start_room(room_id)
      assert_receive {:room_created, %{room_id: ^room_id}}

      # Player joins
      Room.join(room_id, "p1", "Alice")
      assert_receive {:player_joined, %{player_name: "Alice", role: :x}}
      assert_receive {:room_updated, %{room_id: ^room_id, player_count: 1}}

      # Player 2 joins
      Room.join(room_id, "p2", "Bob")
      assert_receive {:player_joined, %{player_name: "Bob", role: :o}}
      assert_receive {:room_updated, %{room_id: ^room_id, status: :in_progress}}

      # Play move
      Room.play_move(room_id, "p1", 0)
      assert_receive {:move_played, %{role: :x, move: 0}}
      assert_receive {:room_updated, %{room_id: ^room_id}}

      # Stop room -> receives :room_closed and :room_deleted
      Room.stop(room_id)
      assert_receive {:room_closed, %{room_id: ^room_id}}
      assert_receive {:room_deleted, %{room_id: ^room_id}}
    end
  end

  describe "timeouts and automatic room cleanup" do
    test "shuts down on empty timeout when room remains deserted", %{room_id: room_id} do
      Phoenix.PubSub.subscribe(Gameroom.PubSub, "room:#{room_id}")
      Phoenix.PubSub.subscribe(Gameroom.PubSub, "rooms:lobby")

      # Start with a very short empty timeout (50ms)
      pid = start_room(room_id, empty_timeout_ms: 50)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :empty_timeout}}, 500
      assert_receive {:room_closed, %{room_id: ^room_id, reason: :empty_timeout}}
      assert_receive {:room_deleted, %{room_id: ^room_id}}
      refute RoomSupervisor.room_exists?(room_id)
    end

    test "cancels empty timer when player joins", %{room_id: room_id} do
      # Start with empty timeout of 100ms
      pid = start_room(room_id, empty_timeout_ms: 100)
      ref = Process.monitor(pid)

      # Alice joins immediately
      Room.join(room_id, "p1", "Alice")

      # Verify room is still alive after 200ms
      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 200
      assert Process.alive?(pid)
    end

    test "shuts down on idle timeout after inactivity", %{room_id: room_id} do
      Phoenix.PubSub.subscribe(Gameroom.PubSub, "room:#{room_id}")

      # Start with idle timeout of 50ms (large empty timeout)
      pid = start_room(room_id, idle_timeout_ms: 50, empty_timeout_ms: 60_000)
      Room.join(room_id, "p1", "Alice")
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :idle_timeout}}, 500
      assert_receive {:room_closed, %{room_id: ^room_id, reason: :idle_timeout}}
      refute RoomSupervisor.room_exists?(room_id)
    end
  end
end
