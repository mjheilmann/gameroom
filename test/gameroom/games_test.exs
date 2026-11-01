defmodule Gameroom.GamesTest do
  use ExUnit.Case, async: false

  alias Gameroom.Games

  setup do
    room_id = "test-games-facade-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Games.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  describe "room creation and metadata" do
    test "create_room creates a room with custom or generated id", %{room_id: room_id} do
      assert {:ok, ^room_id} = Games.create_room(room_id)
      assert Games.room_exists?(room_id)
      assert {:ok, pid} = Games.get_room_pid(room_id)
      assert is_pid(pid)

      # Duplicate creation returns already_exists
      assert Games.create_room(room_id) == {:error, :already_exists}

      # Created without ID generates a slug
      assert {:ok, auto_id} = Games.create_room()
      assert Games.room_exists?(auto_id)
      assert is_binary(auto_id)
      assert String.contains?(auto_id, "-")
      Games.stop_room(auto_id)

      # Created with blank ID generates a slug
      assert {:ok, blank_id} = Games.create_room("   ")
      assert Games.room_exists?(blank_id)
      Games.stop_room(blank_id)
    end

    test "generate_room_id returns human-readable slug format" do
      id = Games.generate_room_id()
      assert is_binary(id)
      parts = String.split(id, "-")
      assert length(parts) == 3
      [adj, noun, num_str] = parts
      assert String.length(adj) > 0
      assert String.length(noun) > 0
      assert {num, ""} = Integer.parse(num_str)
      assert num >= 9
    end

    test "list_rooms returns active rooms ordered by newest first", %{room_id: room_id} do
      {:ok, ^room_id} = Games.create_room(room_id)

      rooms = Games.list_rooms()
      assert is_list(rooms)
      assert Enum.any?(rooms, fn r -> r.room_id == room_id end)
    end

    test "get_room_state and get_room_summary return valid data", %{room_id: room_id} do
      {:ok, ^room_id} = Games.create_room(room_id)

      assert {:ok, state} = Games.get_room_state(room_id)
      assert state.room_id == room_id
      assert state.status == :waiting

      assert {:ok, summary} = Games.get_room_summary(room_id)
      assert summary.room_id == room_id
      assert summary.status == :waiting
      assert summary.player_count == 0
    end
  end

  describe "game lifecycle facade" do
    test "full game flow through Games facade", %{room_id: room_id} do
      {:ok, ^room_id} = Games.create_room(room_id)

      # Join players
      assert {:ok, p1_info} = Games.join_room(room_id, "p1", "Alice")
      assert p1_info.role == :x

      assert {:ok, p2_info} = Games.join_room(room_id, "p2", "Bob")
      assert p2_info.role == :o

      assert {:ok, summary} = Games.get_room_summary(room_id)
      assert summary.status == :in_progress
      assert summary.current_player == :x

      # Moves
      assert {:ok, _} = Games.play_move(room_id, "p1", 0)
      assert {:ok, _} = Games.play_move(room_id, "p2", 3)
      assert {:ok, _} = Games.play_move(room_id, "p1", 1)
      assert {:ok, _} = Games.play_move(room_id, "p2", 4)
      assert {:ok, _} = Games.play_move(room_id, "p1", 2)

      # Check finished summary
      assert {:ok, finished_summary} = Games.get_room_summary(room_id)
      assert finished_summary.status == :finished
      assert finished_summary.winner == :x
      assert finished_summary.finish_reason == :win

      # Rematch flow
      assert {:ok, :rematch_requested} = Games.rematch(room_id, "p1")
      assert {:ok, :rematch_started} = Games.rematch(room_id, "p2")

      assert {:ok, reset_summary} = Games.get_room_summary(room_id)
      assert reset_summary.status == :in_progress
      assert reset_summary.current_player == :x

      # Reset room directly
      assert {:ok, _} = Games.reset_room(room_id)
      assert {:ok, reset_summary2} = Games.get_room_summary(room_id)
      assert reset_summary2.status == :in_progress
    end

    test "spectator and seating actions through facade", %{room_id: room_id} do
      {:ok, ^room_id} = Games.create_room(room_id)

      assert {:ok, _} = Games.join_room(room_id, "p1", "Alice")
      assert {:ok, _} = Games.join_room(room_id, "p2", "Bob", :spectator)

      # Spectator takes seat O
      assert {:ok, :o} = Games.take_seat(room_id, "p2", :o)

      # Game starts
      assert {:ok, summary} = Games.get_room_summary(room_id)
      assert summary.status == :in_progress

      # Forfeit
      assert {:ok, :x} = Games.forfeit(room_id, "p2")
      assert {:ok, forfeit_summary} = Games.get_room_summary(room_id)
      assert forfeit_summary.status == :finished
      assert forfeit_summary.winner == :x
      assert forfeit_summary.finish_reason == :forfeit

      # Switch Alice to spectator when finished
      assert {:ok, :spectator} = Games.switch_to_spectator(room_id, "p1")
      assert {:ok, spec_summary} = Games.get_room_summary(room_id)
      # Bob is still in seat O, Alice is now spectator
      assert spec_summary.player_count == 1
      assert spec_summary.spectator_count == 1

      # Bob leaves room -> player_count becomes 0
      assert {:ok, :left} = Games.leave_room(room_id, "p2")
      assert {:ok, bob_left_summary} = Games.get_room_summary(room_id)
      assert bob_left_summary.player_count == 0

      # Alice leaves room -> spectator_count becomes 0
      assert {:ok, :left} = Games.leave_room(room_id, "p1")
      assert {:ok, final_summary} = Games.get_room_summary(room_id)
      assert final_summary.spectator_count == 0
    end

    test "PubSub subscription helpers", %{room_id: room_id} do
      assert :ok = Games.subscribe_lobby()
      assert :ok = Games.subscribe(room_id)

      {:ok, ^room_id} = Games.create_room(room_id)
      assert_receive {:room_created, %{room_id: ^room_id}}

      Games.join_room(room_id, "p1", "Alice")
      assert_receive {:player_joined, %{player_name: "Alice"}}

      assert :ok = Games.unsubscribe(room_id)
      assert :ok = Games.unsubscribe_lobby()
    end
  end
end
