defmodule Gameroom.Games.TicTacToeTest do
  use ExUnit.Case, async: true

  alias Gameroom.Games.TicTacToe

  describe "new_game/1" do
    test "initializes a fresh game with default player :x" do
      game = TicTacToe.new_game()

      assert game.current_player == :x
      assert game.status == :in_progress
      assert game.winning_line == nil
      assert game.moves_count == 0
      assert game.history == []
      assert map_size(game.board) == 9

      for r <- 0..2, c <- 0..2 do
        assert Map.get(game.board, {r, c}) == nil
      end
    end

    test "initializes a game with custom starting_player :o" do
      game = TicTacToe.new_game(starting_player: :o)
      assert game.current_player == :o
      assert game.status == :in_progress
    end

    test "raises ArgumentError when starting_player is invalid" do
      assert_raise ArgumentError, ~r/starting_player must be :x or :o/, fn ->
        TicTacToe.new_game(starting_player: :invalid)
      end
    end
  end

  describe "normalize_move/1" do
    test "accepts valid coordinate tuples {0..2, 0..2}" do
      assert TicTacToe.normalize_move({0, 0}) == {:ok, {0, 0}}
      assert TicTacToe.normalize_move({1, 2}) == {:ok, {1, 2}}
      assert TicTacToe.normalize_move({2, 1}) == {:ok, {2, 1}}
    end

    test "accepts integer indices 0..8 and converts to {row, col}" do
      assert TicTacToe.normalize_move(0) == {:ok, {0, 0}}
      assert TicTacToe.normalize_move(1) == {:ok, {0, 1}}
      assert TicTacToe.normalize_move(2) == {:ok, {0, 2}}
      assert TicTacToe.normalize_move(3) == {:ok, {1, 0}}
      assert TicTacToe.normalize_move(4) == {:ok, {1, 1}}
      assert TicTacToe.normalize_move(5) == {:ok, {1, 2}}
      assert TicTacToe.normalize_move(6) == {:ok, {2, 0}}
      assert TicTacToe.normalize_move(7) == {:ok, {2, 1}}
      assert TicTacToe.normalize_move(8) == {:ok, {2, 2}}
    end

    test "rejects out of bounds coordinates and indices" do
      assert TicTacToe.normalize_move(-1) == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move(9) == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move({-1, 0}) == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move({0, 3}) == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move({3, 3}) == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move("invalid") == {:error, :invalid_coordinate}
      assert TicTacToe.normalize_move(nil) == {:error, :invalid_coordinate}
    end
  end

  describe "valid_move?/2 and valid_move?/3" do
    test "returns true for empty cell and current player turn" do
      game = TicTacToe.new_game()
      assert TicTacToe.valid_move?(game, :x, {0, 0})
      assert TicTacToe.valid_move?(game, :x, 4)
      assert TicTacToe.valid_move?(game, {1, 1})
      assert TicTacToe.valid_move?(game, 0)
    end

    test "returns false when player is not current player" do
      game = TicTacToe.new_game()
      assert game.current_player == :x
      refute TicTacToe.valid_move?(game, :o, {0, 0})
    end

    test "returns false when cell is already occupied" do
      {:ok, game} = TicTacToe.new_game() |> TicTacToe.apply_move(:x, {0, 0})
      refute TicTacToe.valid_move?(game, :o, {0, 0})
    end

    test "returns false for invalid moves" do
      game = TicTacToe.new_game()
      refute TicTacToe.valid_move?(game, :x, {5, 5})
      refute TicTacToe.valid_move?(game, :x, 10)
    end

    test "returns false when game is already finished" do
      # Quick win for X: row 0
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {1, 0}},
          {:x, {0, 1}},
          {:o, {1, 1}},
          {:x, {0, 2}}
        ])

      assert TicTacToe.game_over?(game)
      refute TicTacToe.valid_move?(game, :o, {2, 2})
      refute TicTacToe.valid_move?(game, :x, {2, 2})
    end
  end

  describe "apply_move/2 and apply_move/3" do
    test "advances turn, updates board, moves_count, and history" do
      game = TicTacToe.new_game()
      assert {:ok, game} = TicTacToe.apply_move(game, :x, {1, 1})

      assert game.current_player == :o
      assert game.moves_count == 1
      assert game.history == [{:x, {1, 1}}]
      assert TicTacToe.get_cell(game, {1, 1}) == :x
      assert TicTacToe.get_cell(game, 4) == :x

      assert {:ok, game} = TicTacToe.apply_move(game, :o, 0)
      assert game.current_player == :x
      assert game.moves_count == 2
      assert game.history == [{:x, {1, 1}}, {:o, {0, 0}}]
      assert TicTacToe.get_cell(game, {0, 0}) == :o
    end

    test "apply_move/2 infers the current player" do
      game = TicTacToe.new_game()
      assert {:ok, game} = TicTacToe.apply_move(game, {0, 0})
      assert game.current_player == :o
      assert {:ok, game} = TicTacToe.apply_move(game, {0, 1})
      assert game.current_player == :x
    end

    test "returns error when not player's turn" do
      game = TicTacToe.new_game()
      # :o tries to move when it is :x's turn
      assert TicTacToe.apply_move(game, :o, {0, 0}) == {:error, :not_player_turn}
      refute TicTacToe.valid_move?(game, :o, {0, 0})

      # :x moves successfully
      assert {:ok, game} = TicTacToe.apply_move(game, :x, {0, 0})

      # :x immediately tries to move again out of turn
      assert TicTacToe.apply_move(game, :x, {1, 1}) == {:error, :not_player_turn}
      refute TicTacToe.valid_move?(game, :x, {1, 1})
    end

    test "returns error when cell is occupied" do
      {:ok, game} = TicTacToe.new_game() |> TicTacToe.apply_move(:x, {0, 0})
      assert TicTacToe.apply_move(game, :o, {0, 0}) == {:error, :cell_occupied}
    end

    test "returns error on invalid coordinate" do
      game = TicTacToe.new_game()
      assert TicTacToe.apply_move(game, :x, {3, 0}) == {:error, :invalid_coordinate}
      assert TicTacToe.apply_move(game, :x, 99) == {:error, :invalid_coordinate}
    end

    test "returns error when game is already over" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, 0},
          {:o, 3},
          {:x, 1},
          {:o, 4},
          {:x, 2}
        ])

      assert TicTacToe.game_over?(game)
      assert TicTacToe.apply_move(game, :o, 5) == {:error, :game_over}
    end
  end

  describe "win detection" do
    test "detects horizontal win on row 0" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {1, 0}},
          {:x, {0, 1}},
          {:o, {1, 1}},
          {:x, {0, 2}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 0}, {0, 1}, {0, 2}]
      assert TicTacToe.winner(game) == :x
      assert TicTacToe.game_over?(game)
      refute TicTacToe.draw?(game)
    end

    test "detects horizontal win on row 1" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {1, 0}},
          {:o, {0, 0}},
          {:x, {1, 1}},
          {:o, {0, 1}},
          {:x, {1, 2}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{1, 0}, {1, 1}, {1, 2}]
    end

    test "detects horizontal win on row 2" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {2, 0}},
          {:o, {0, 0}},
          {:x, {2, 1}},
          {:o, {0, 1}},
          {:x, {2, 2}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{2, 0}, {2, 1}, {2, 2}]
    end

    test "detects vertical win on column 0" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {0, 1}},
          {:x, {1, 0}},
          {:o, {1, 1}},
          {:x, {2, 0}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 0}, {1, 0}, {2, 0}]
    end

    test "detects vertical win on column 1" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 1}},
          {:o, {0, 0}},
          {:x, {1, 1}},
          {:o, {1, 0}},
          {:x, {2, 1}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 1}, {1, 1}, {2, 1}]
    end

    test "detects vertical win on column 2" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 2}},
          {:o, {0, 0}},
          {:x, {1, 2}},
          {:o, {1, 0}},
          {:x, {2, 2}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 2}, {1, 2}, {2, 2}]
    end

    test "detects primary diagonal win" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {0, 1}},
          {:x, {1, 1}},
          {:o, {0, 2}},
          {:x, {2, 2}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 0}, {1, 1}, {2, 2}]
    end

    test "detects secondary anti-diagonal win" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 2}},
          {:o, {0, 0}},
          {:x, {1, 1}},
          {:o, {0, 1}},
          {:x, {2, 0}}
        ])

      assert game.status == {:winner, :x}
      assert game.winning_line == [{0, 2}, {1, 1}, {2, 0}]
    end

    test "detects win by player :o" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {1, 0}},
          {:x, {0, 1}},
          {:o, {1, 1}},
          {:x, {2, 2}},
          {:o, {1, 2}}
        ])

      assert game.status == {:winner, :o}
      assert game.winning_line == [{1, 0}, {1, 1}, {1, 2}]
      assert TicTacToe.winner(game) == :o
    end
  end

  describe "draw detection" do
    test "detects a full board draw" do
      # Grid sequence without a win:
      # X O X
      # X X O
      # O X O
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {0, 1}},
          {:x, {0, 2}},
          {:o, {1, 2}},
          {:x, {1, 0}},
          {:o, {2, 0}},
          {:x, {1, 1}},
          {:o, {2, 2}},
          {:x, {2, 1}}
        ])

      assert game.moves_count == 9
      assert game.status == :draw
      assert game.winning_line == nil
      assert TicTacToe.draw?(game)
      assert TicTacToe.game_over?(game)
      assert TicTacToe.winner(game) == nil
      assert TicTacToe.available_moves(game) == []
    end
  end

  describe "helpers and utilities" do
    test "available_moves/1 tracks remaining cells and returns empty when game is won" do
      game = TicTacToe.new_game()
      assert length(TicTacToe.available_moves(game)) == 9

      {:ok, game} = TicTacToe.apply_move(game, {0, 0})
      available = TicTacToe.available_moves(game)
      assert length(available) == 8
      refute {0, 0} in available

      # Play to win
      game =
        game
        |> play_moves([
          {:o, {1, 0}},
          {:x, {0, 1}},
          {:o, {1, 1}},
          {:x, {0, 2}}
        ])

      assert TicTacToe.available_moves(game) == []
    end

    test "get_cell/2 returns cell contents or nil" do
      game = TicTacToe.new_game()
      assert TicTacToe.get_cell(game, {0, 0}) == nil
      assert TicTacToe.get_cell(game, 0) == nil
      assert TicTacToe.get_cell(game, 99) == nil

      {:ok, game} = TicTacToe.apply_move(game, :x, {0, 0})
      assert TicTacToe.get_cell(game, {0, 0}) == :x
      assert TicTacToe.get_cell(game, 0) == :x
    end

    test "next_player/1 alternates between players" do
      assert TicTacToe.next_player(:x) == :o
      assert TicTacToe.next_player(:o) == :x
    end

    test "render_ascii/1 formats the board state" do
      game =
        TicTacToe.new_game()
        |> play_moves([
          {:x, {0, 0}},
          {:o, {1, 1}}
        ])

      ascii = TicTacToe.render_ascii(game)
      assert ascii =~ "X | · | ·"
      assert ascii =~ "· | O | ·"
      assert ascii =~ "---------"
    end
  end

  # Helper to chain moves in tests
  defp play_moves(game, moves) do
    Enum.reduce(moves, game, fn {player, move}, acc ->
      {:ok, next_game} = TicTacToe.apply_move(acc, player, move)
      next_game
    end)
  end
end
