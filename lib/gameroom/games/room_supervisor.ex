defmodule Gameroom.Games.RoomSupervisor do
  @moduledoc """
  Supervision and lifecycle management for dynamic `Gameroom.Games.Room` processes.

  Active game rooms are started under this DynamicSupervisor and registered
  with `Gameroom.Games.RoomRegistry`.
  """

  alias Gameroom.Games.Room
  alias Gameroom.Games.RoomRegistry

  @supervisor __MODULE__
  @registry RoomRegistry

  @doc """
  Starts a new game room process supervised under `Gameroom.Games.RoomSupervisor`.

  ## Options
    * `:room_id` - Unique room identifier (required)
    * `:game_module` - Game engine module (default `Gameroom.Games.TicTacToe`)
    * `:game_opts` - Options passed to `game_module.new_game/1` (default `[]`)
    * `:idle_timeout_ms` - Inactivity timeout in ms (default 30 mins)
    * `:empty_timeout_ms` - Empty room timeout in ms (default 5 mins)
    * `:pubsub` - Phoenix.PubSub server (default `Gameroom.PubSub`)
  """
  @spec start_room(keyword() | map()) :: DynamicSupervisor.on_start_child()
  def start_room(opts) do
    DynamicSupervisor.start_child(@supervisor, {Room, opts})
  end

  @doc """
  Stops an active game room and terminates its process.
  """
  @spec stop_room(String.t() | pid(), term()) :: :ok | {:error, :not_found}
  def stop_room(room_id_or_pid, reason \\ :normal) do
    case room_pid(room_id_or_pid) do
      {:ok, pid} ->
        Room.stop(pid, reason)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds the PID of an active room by room_id or validates an existing PID.
  """
  @spec room_pid(String.t() | pid()) :: {:ok, pid()} | {:error, :not_found}
  def room_pid(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :not_found}
  end

  def room_pid(room_id) when is_binary(room_id) do
    case Registry.lookup(@registry, room_id) do
      [{pid, _value}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: {:error, :not_found}

      [] ->
        {:error, :not_found}
    end
  end

  def room_pid(_), do: {:error, :not_found}

  @doc """
  Checks if a room currently exists and is alive.
  """
  @spec room_exists?(String.t() | pid()) :: boolean()
  def room_exists?(room_id_or_pid) do
    case room_pid(room_id_or_pid) do
      {:ok, _pid} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Returns the count of active room processes.
  """
  @spec count_rooms() :: non_neg_integer()
  def count_rooms do
    Registry.count(@registry)
  end

  @doc """
  Returns a list of all active room IDs.
  """
  @spec which_room_ids() :: [String.t()]
  def which_room_ids do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  @doc """
  Returns children currently supervised by RoomSupervisor.
  """
  @spec which_children() :: [{:undefined, pid(), :worker, [module()]}]
  def which_children do
    DynamicSupervisor.which_children(@supervisor)
  end
end
