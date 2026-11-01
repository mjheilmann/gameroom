defmodule Gameroom.Games.RoomSupervisorTest do
  use ExUnit.Case, async: false

  alias Gameroom.Games.RoomSupervisor
  alias Gameroom.Games.Room

  setup do
    room_id = "test-sup-room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      RoomSupervisor.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  describe "room supervision lifecycle" do
    test "starts, looks up, and stops a supervised room process", %{room_id: room_id} do
      refute RoomSupervisor.room_exists?(room_id)
      assert RoomSupervisor.room_pid(room_id) == {:error, :not_found}

      assert {:ok, pid} = RoomSupervisor.start_room(room_id: room_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert RoomSupervisor.room_exists?(room_id)
      assert RoomSupervisor.room_pid(room_id) == {:ok, pid}
      assert RoomSupervisor.room_pid(pid) == {:ok, pid}

      assert room_id in RoomSupervisor.which_room_ids()
      assert RoomSupervisor.count_rooms() >= 1

      assert RoomSupervisor.stop_room(room_id) == :ok
      # Wait briefly for process to exit
      refute Process.alive?(pid)
      refute RoomSupervisor.room_exists?(room_id)
      assert RoomSupervisor.room_pid(room_id) == {:error, :not_found}
    end

    test "prevents duplicate rooms with the same room_id", %{room_id: room_id} do
      assert {:ok, pid} = RoomSupervisor.start_room(room_id: room_id)
      assert {:error, {:already_started, ^pid}} = RoomSupervisor.start_room(room_id: room_id)
    end

    test "handles stopping a non-existent room" do
      assert RoomSupervisor.stop_room("non-existent-room-id") == {:error, :not_found}
    end

    test "which_children lists active room workers", %{room_id: room_id} do
      assert {:ok, pid} = RoomSupervisor.start_room(room_id: room_id)
      children = RoomSupervisor.which_children()

      assert Enum.any?(children, fn {_, child_pid, :worker, [Room]} ->
               child_pid == pid
             end)
    end
  end
end

