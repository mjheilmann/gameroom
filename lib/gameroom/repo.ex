defmodule Gameroom.Repo do
  use Ecto.Repo,
    otp_app: :gameroom,
    adapter: Ecto.Adapters.SQLite3
end
