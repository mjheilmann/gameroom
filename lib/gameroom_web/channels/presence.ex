defmodule GameroomWeb.Presence do
  use Phoenix.Presence, otp_app: :gameroom, pubsub_server: Gameroom.PubSub
end
