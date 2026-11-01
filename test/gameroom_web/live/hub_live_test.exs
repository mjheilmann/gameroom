defmodule GameroomWeb.HubLiveTest do
  use GameroomWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Gameroom.Games
  alias Gameroom.Games.RoomSupervisor

  setup do
    on_exit(fn ->
      for room_id <- RoomSupervisor.which_room_ids() do
        RoomSupervisor.stop_room(room_id)
      end
    end)

    :ok
  end

  describe "Lobby mount and presence" do
    test "mounts lobby with presence and player nickname", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Tabletop Games Lobby"
      assert has_element?(view, "#create-room-form")
      assert has_element?(view, "#join-code-form")
      assert has_element?(view, "#player-nickname-display")
      assert has_element?(view, "#online-players-count")
      assert has_element?(view, "#active-rooms-count")
      assert has_element?(view, "#rooms-stream")
    end

    test "renders empty rooms state when no active rooms exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#empty-rooms-state")
      assert has_element?(view, "#empty-state-randomize-btn")
    end
  end

  describe "nickname management" do
    test "allows inline editing and saving of player nickname", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Click edit
      view |> element("#edit-nickname-btn") |> render_click()
      assert has_element?(view, "#nickname-form")

      # Submit invalid short nickname
      view
      |> form("#nickname-form", %{"player" => %{"nickname" => "A"}})
      |> render_submit()

      assert render(view) =~ "Nickname must be between 2 and 24 characters"

      # Submit valid nickname
      view
      |> form("#nickname-form", %{"player" => %{"nickname" => "CosmicMaster"}})
      |> render_submit()

      assert has_element?(view, "#player-nickname-display", "CosmicMaster")
      refute has_element?(view, "#nickname-form")
      assert render(view) =~ "Nickname updated to"
    end

    test "allows cancelling nickname edit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#edit-nickname-btn") |> render_click()
      assert has_element?(view, "#nickname-form")

      view |> element("#cancel-nickname-btn") |> render_click()
      refute has_element?(view, "#nickname-form")
      assert has_element?(view, "#player-nickname-display")
    end

    test "restores stored nickname via client event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "restore_nickname", %{"nickname" => "RestoredFox42"})
      assert has_element?(view, "#player-nickname-display", "RestoredFox42")
    end
  end

  describe "room creation and quick join" do
    test "randomizes room code on button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      input_before =
        view
        |> element("#create-room-form input[name='room[room_id]']")
        |> render()

      view |> element("#randomize-slug-btn") |> render_click()

      input_after =
        view
        |> element("#create-room-form input[name='room[room_id]']")
        |> render()

      refute input_before == input_after
    end

    test "creates new game room and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      room_id = "custom-test-room-#{System.unique_integer([:positive])}"

      {:error, {:live_redirect, %{to: target_path}}} =
        view
        |> form("#create-room-form", %{
          "room" => %{"room_id" => room_id, "role" => "x"}
        })
        |> render_submit()

      assert target_path == ~p"/games/#{room_id}"
      assert Games.room_exists?(room_id)
    end

    test "shows error flash when attempting to create duplicate room", %{conn: conn} do
      room_id = "duplicate-room-#{System.unique_integer([:positive])}"
      {:ok, ^room_id} = Games.create_room(room_id)

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#create-room-form", %{
        "room" => %{"room_id" => room_id, "role" => "x"}
      })
      |> render_submit()

      assert render(view) =~ "already exists"
    end

    test "direct join with code navigates to room", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      room_id = "join-code-room-123"

      {:error, {:live_redirect, %{to: target_path}}} =
        view
        |> form("#join-code-form", %{"room_code" => room_id})
        |> render_submit()

      assert target_path == ~p"/games/#{room_id}"
    end

    test "direct join with empty code shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#join-code-form", %{"room_code" => "   "})
      |> render_submit()

      assert render(view) =~ "Please enter a valid room code"
    end
  end

  describe "active rooms browser and live updates" do
    test "displays active rooms with seats and status badges", %{conn: conn} do
      room_id = "active-browser-room-#{System.unique_integer([:positive])}"
      {:ok, ^room_id} = Games.create_room(room_id)
      Games.join_room(room_id, "p1", "Alice")

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#rooms-stream")
      assert has_element?(view, "#join-room-btn-#{room_id}")
      assert render(view) =~ room_id
      assert render(view) =~ "Alice"
      assert render(view) =~ "Waiting"
      refute has_element?(view, "#empty-rooms-state")
    end

    test "receives real-time room updates via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#empty-rooms-state")

      # Create room from outside LiveView (simulating another user)
      room_id = "realtime-room-#{System.unique_integer([:positive])}"
      {:ok, ^room_id} = Games.create_room(room_id)

      # Stream receives :room_created
      assert has_element?(view, "#join-room-btn-#{room_id}")
      refute has_element?(view, "#empty-rooms-state")

      # Player 1 and Player 2 join (room becomes in progress)
      Games.join_room(room_id, "p1", "Alice")
      Games.join_room(room_id, "p2", "Bob")

      # Stream receives :room_updated
      assert has_element?(view, "#spectate-room-btn-#{room_id}")
      assert render(view) =~ "Turn: X"

      # Stop room -> stream receives :room_deleted
      Games.stop_room(room_id)
      refute has_element?(view, "#spectate-room-btn-#{room_id}")
    end

    test "filters rooms by status and search query", %{conn: conn} do
      room1 = "filter-waiting-#{System.unique_integer([:positive])}"
      room2 = "filter-progress-#{System.unique_integer([:positive])}"

      {:ok, ^room1} = Games.create_room(room1)
      Games.join_room(room1, "p1", "Alice")

      {:ok, ^room2} = Games.create_room(room2)
      Games.join_room(room2, "p1", "Bob")
      Games.join_room(room2, "p2", "Charlie")

      {:ok, view, _html} = live(conn, ~p"/")

      # Both rooms visible initially
      assert has_element?(view, "#join-room-btn-#{room1}")
      assert has_element?(view, "#spectate-room-btn-#{room2}")

      # Filter: Waiting
      view |> element("#filter-waiting-btn") |> render_click()
      assert has_element?(view, "#join-room-btn-#{room1}")
      refute has_element?(view, "#spectate-room-btn-#{room2}")

      # Filter: In Progress
      view |> element("#filter-in-progress-btn") |> render_click()
      refute has_element?(view, "#join-room-btn-#{room1}")
      assert has_element?(view, "#spectate-room-btn-#{room2}")

      # Filter: All
      view |> element("#filter-all-btn") |> render_click()
      assert has_element?(view, "#join-room-btn-#{room1}")
      assert has_element?(view, "#spectate-room-btn-#{room2}")

      # Search by room ID
      view
      |> form("#search-rooms-form", %{"query" => room1})
      |> render_change()

      assert has_element?(view, "#join-room-btn-#{room1}")
      refute has_element?(view, "#spectate-room-btn-#{room2}")
    end
  end
end

