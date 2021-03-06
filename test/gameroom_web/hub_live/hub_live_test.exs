defmodule GameroomWeb.GameHubTest do
  use GameroomWeb.ConnCase

  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, "/")
    assert disconnected_html =~ "Gameroom · Phoenix Framework"
    assert render(page_live) =~ "~~  (me) ~~"
  end
end
