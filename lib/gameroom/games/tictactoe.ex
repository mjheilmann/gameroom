defmodule Gameroom.Games.Tictactoe do
  defstruct places: []

  alias Gameroom.Games.Tictactoe, as: Board

  @pieces [:x, :o]
  @initial_board [nil, nil, nil, nil, nil, nil, nil, nil, nil]

  def new_board, do: %Board{places: @initial_board}

  def move(%Board{places: board}, piece, pos) do
    with true <- piece in @pieces,
         true <- is_integer(pos),
         true <- pos >= 0,
         true <- pos <= 8,
         true <- valid_board?(board),
         nil <- Enum.at(board, pos, :error) do
      {:ok, %Board{places: List.replace_at(board, pos, piece)}}
    else
      _ -> {:error, "invalid move"}
    end
  end

  defp valid_board?([_, _, _, _, _, _, _, _, _] = board) do
    [nil, :x, :o | board] |> Enum.uniq() |> List.to_tuple() == {nil, :x, :o}
  end

  defp valid_board?(_), do: false

  def winner?(%Board{places: board}, piece) do
    with true <- piece in @pieces,
         true <- valid_board?(board) do
      check_winner?(board, piece)
    else
      _ -> false
    end
  end

  defp check_winner?([x, x, x, _, _, _, _, _, _], x) when x in @pieces, do: true
  defp check_winner?([_, _, _, x, x, x, _, _, _], x) when x in @pieces, do: true
  defp check_winner?([_, _, _, _, _, _, x, x, x], x) when x in @pieces, do: true
  defp check_winner?([x, _, _, x, _, _, x, _, _], x) when x in @pieces, do: true
  defp check_winner?([_, x, _, _, x, _, _, x, _], x) when x in @pieces, do: true
  defp check_winner?([_, _, x, _, _, x, _, _, x], x) when x in @pieces, do: true
  defp check_winner?([x, _, _, _, x, _, _, _, x], x) when x in @pieces, do: true
  defp check_winner?([_, _, x, _, x, _, x, _, _], x) when x in @pieces, do: true
  defp check_winner?(_, _), do: false
end
