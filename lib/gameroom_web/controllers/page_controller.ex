defmodule GameroomWeb.PageController do
  use GameroomWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
