defmodule GameroomWeb.Plugs.GuestSession do
  @moduledoc """
  Ensures that browser sessions have a persistent guest `player_id`
  and an initial friendly `player_name`.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> ensure_session_key("player_id", &Ecto.UUID.generate/0)
    |> ensure_session_key("player_name", &Gameroom.Games.generate_player_name/0)
  end

  defp ensure_session_key(conn, key, generator_fn) do
    case get_session(conn, key) do
      nil -> put_session(conn, key, generator_fn.())
      _val -> conn
    end
  end
end

