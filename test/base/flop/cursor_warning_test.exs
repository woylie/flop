defmodule Flop.CursorWarningTest do
  # async: false because capture_log also captures logs from concurrent tests
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Flop.Cursor

  describe "get_cursors/3" do
    test "logs a warning if a tiebreaker value is nil" do
      log =
        capture_log(fn ->
          Cursor.get_cursors([%{name: "George"}], [:name, :id], for: MyApp.Pet)
        end)

      assert log =~ "nil tiebreaker value in cursor"
      assert log =~ ":id"
      assert log =~ "MyApp.Pet"
    end

    test "does not log a warning if the tiebreaker values are set" do
      log =
        capture_log(fn ->
          Cursor.get_cursors([%{id: 1, name: "George"}], [:name, :id],
            for: MyApp.Pet
          )
        end)

      assert log == ""
    end
  end
end
