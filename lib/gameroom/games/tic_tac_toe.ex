defmodule Gameroom.Games.TicTacToe do
  @moduledoc """
  Pure functional game logic engine for 3x3 Tic-Tac-Toe.

  Manages board state, turn alternation, legal move validation, win detection
  (rows, columns, diagonals), draw detection, and move history.
  """

  @type player :: :x | :o
  @type coordinate :: {0..2, 0..2}
  @type index_move :: 0..8
  @type move :: coordinate | index_move
  @type status :: :in_progress | {:winner, player} | :draw
  @type board :: %{coordinate => player | nil}

  @type t :: %__MODULE__{
          board: board(),
          current_player: player(),
          status: status(),
          winning_line: [coordinate()] | nil,
          moves_count: non_neg_integer(),
          history: [{player(), coordinate()}]
        }

  @enforce_keys [:board, :current_player, :status]
  defstruct [
    :board,
    :current_player,
    :status,
    winning_line: nil,
    moves_count: 0,
    history: []
  ]

  @winning_lines [
    # Rows
    [{0, 0}, {0, 1}, {0, 2}],
    [{1, 0}, {1, 1}, {1, 2}],
    [{2, 0}, {2, 1}, {2, 2}],
    # Columns
    [{0, 0}, {1, 0}, {2, 0}],
    [{0, 1}, {1, 1}, {2, 1}],
    [{0, 2}, {1, 2}, {2, 2}],
    # Diagonals
    [{0, 0}, {1, 1}, {2, 2}],
    [{0, 2}, {1, 1}, {2, 0}]
  ]

  @doc """
  Returns the list of valid player roles for this game.
  """
  @spec player_roles() :: [player()]
  def player_roles, do: [:x, :o]

  @doc """
  Creates a new Tic-Tac-Toe game.

  ## Options
    * `:starting_player` - `:x` (default) or `:o`
  """
  @spec new_game(keyword()) :: t()
  def new_game(opts \\ []) do
    starting_player = Keyword.get(opts, :starting_player, :x)

    unless starting_player in [:x, :o] do
      raise ArgumentError, "starting_player must be :x or :o, got: #{inspect(starting_player)}"
    end

    board =
      for r <- 0..2, c <- 0..2, into: %{} do
        {{r, c}, nil}
      end

    %__MODULE__{
      board: board,
      current_player: starting_player,
      status: :in_progress,
      winning_line: nil,
      moves_count: 0,
      history: []
    }
  end

  @doc """
  Normalizes a move into a `{row, col}` coordinate tuple.
  Accepts `{row, col}` (0..2) or an integer index (0..8).
  """
  @spec normalize_move(term()) :: {:ok, coordinate()} | {:error, :invalid_coordinate}
  def normalize_move(idx) when is_integer(idx) and idx in 0..8 do
    {:ok, {div(idx, 3), rem(idx, 3)}}
  end

  def normalize_move({r, c}) when is_integer(r) and is_integer(c) and r in 0..2 and c in 0..2 do
    {:ok, {r, c}}
  end

  def normalize_move(_), do: {:error, :invalid_coordinate}

  @doc """
  Checks if a move is valid for the current player.
  """
  @spec valid_move?(t(), move()) :: boolean()
  def valid_move?(%__MODULE__{current_player: player} = game, move) do
    valid_move?(game, player, move)
  end

  @doc """
  Checks if a move is valid for the given player.
  """
  @spec valid_move?(t(), player(), move()) :: boolean()
  def valid_move?(%__MODULE__{status: :in_progress} = game, player, move) do
    with true <- player == game.current_player,
         {:ok, coord} <- normalize_move(move) do
      Map.get(game.board, coord) == nil
    else
      _ -> false
    end
  end

  def valid_move?(%__MODULE__{}, _player, _move), do: false

  @doc """
  Applies a move using the game's current player.
  """
  @spec apply_move(t(), move()) :: {:ok, t()} | {:error, term()}
  def apply_move(%__MODULE__{current_player: player} = game, move) do
    apply_move(game, player, move)
  end

  @doc """
  Applies a move for the specified player.
  Returns `{:ok, new_game}` or `{:error, reason}`.
  """
  @spec apply_move(t(), player(), move()) ::
          {:ok, t()}
          | {:error, :game_over | :not_player_turn | :invalid_coordinate | :cell_occupied}
  def apply_move(%__MODULE__{status: status}, _player, _move) when status != :in_progress do
    {:error, :game_over}
  end

  def apply_move(%__MODULE__{current_player: current_player}, player, _move)
      when player != current_player do
    {:error, :not_player_turn}
  end

  def apply_move(%__MODULE__{} = game, player, move) do
    case normalize_move(move) do
      {:error, reason} ->
        {:error, reason}

      {:ok, coord} ->
        case Map.get(game.board, coord) do
          nil ->
            {:ok, execute_move(game, player, coord)}

          _occupied ->
            {:error, :cell_occupied}
        end
    end
  end

  @doc """
  Returns the current status of the game (`:in_progress`, `{:winner, player}`, or `:draw`).
  """
  @spec game_status(t()) :: status()
  def game_status(%__MODULE__{status: status}), do: status

  @doc """
  Returns the player whose turn it currently is, or `nil` if the game is over.
  Useful for client reporting and UI turn indicators.
  """
  @spec current_player(t()) :: player() | nil
  def current_player(%__MODULE__{status: :in_progress, current_player: player}), do: player
  def current_player(%__MODULE__{}), do: nil

  @doc """
  Returns true if the game is finished (winner or draw).
  """
  @spec game_over?(t()) :: boolean()
  def game_over?(%__MODULE__{status: status}), do: status != :in_progress

  @doc """
  Returns true if the game ended in a draw.
  """
  @spec draw?(t()) :: boolean()
  def draw?(%__MODULE__{status: status}), do: status == :draw

  @doc """
  Returns the winning player (`:x` or `:o`) or `nil` if there is no winner.
  """
  @spec winner(t()) :: player() | nil
  def winner(%__MODULE__{status: {:winner, player}}), do: player
  def winner(%__MODULE__{}), do: nil

  @doc """
  Returns the player in a given cell, or nil if empty.
  """
  @spec get_cell(t(), move()) :: player() | nil
  def get_cell(%__MODULE__{board: board}, move) do
    case normalize_move(move) do
      {:ok, coord} -> Map.get(board, coord)
      {:error, _} -> nil
    end
  end

  @doc """
  Returns all empty coordinates available for moves.
  Returns `[]` if the game is already over.
  """
  @spec available_moves(t()) :: [coordinate()]
  def available_moves(%__MODULE__{status: status}) when status != :in_progress, do: []

  def available_moves(%__MODULE__{board: board}) do
    for {coord, val} <- board, is_nil(val) do
      coord
    end
    |> Enum.sort()
  end

  @doc """
  Returns the opponent of the given player.
  """
  @spec next_player(player()) :: player()
  def next_player(:x), do: :o
  def next_player(:o), do: :x

  @doc """
  Returns an ASCII string representation of the 3x3 board.
  Useful for debugging and logs.
  """
  @spec render_ascii(t()) :: String.t()
  def render_ascii(%__MODULE__{board: board}) do
    for r <- 0..2 do
      for c <- 0..2 do
        case Map.get(board, {r, c}) do
          :x -> "X"
          :o -> "O"
          nil -> "·"
        end
      end
      |> Enum.join(" | ")
    end
    |> Enum.join("\n---------\n")
  end

  # --- Internal Helpers ---

  defp execute_move(%__MODULE__{} = game, player, coord) do
    new_board = Map.put(game.board, coord, player)
    new_moves_count = game.moves_count + 1
    new_history = game.history ++ [{player, coord}]

    case find_winning_line(new_board, player) do
      [_c1, _c2, _c3] = line ->
        %__MODULE__{
          game
          | board: new_board,
            status: {:winner, player},
            winning_line: line,
            moves_count: new_moves_count,
            history: new_history
        }

      nil ->
        if new_moves_count == 9 do
          %__MODULE__{
            game
            | board: new_board,
              status: :draw,
              winning_line: nil,
              moves_count: new_moves_count,
              history: new_history
          }
        else
          %__MODULE__{
            game
            | board: new_board,
              current_player: next_player(player),
              status: :in_progress,
              winning_line: nil,
              moves_count: new_moves_count,
              history: new_history
          }
        end
    end
  end

  defp find_winning_line(board, player) do
    Enum.find(@winning_lines, fn [c1, c2, c3] ->
      Map.get(board, c1) == player and
        Map.get(board, c2) == player and
        Map.get(board, c3) == player
    end)
  end
end
