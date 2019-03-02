defmodule JobBoard.BotTest do
  use ExUnit.Case, async: true

  import Mox

  alias JobBoard.{
    Bot,
    HTTPClient
  }

  setup :verify_on_exit!

  @issue %{
    "title" => "Dummy",
    "number" => 1,
    "labels" => [],
    "created_at" => nil
  }

  describe "perform_issue/2" do
    test "closes the issue if it is expired" do
      created_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-101 * 24 * 60 * 60)
        |> NaiveDateTime.to_iso8601()

      issue = %{@issue | "created_at" => created_at}

      expect(HTTPClient.Mock, :request, fn :patch, req_url, _, req_body, _ ->
        assert IO.iodata_to_binary(req_url) == "https://api.github.com/repos/foo/bar/issues/1"

        assert Jason.decode!(req_body) == %{
                 "labels" => ["Expired"],
                 "state" => "closed"
               }

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      expect(HTTPClient.Mock, :request, fn :post, req_url, _, _, _ ->
        assert IO.iodata_to_binary(req_url) ==
                 "https://api.github.com/repos/foo/bar/issues/1/comments"

        {:ok, 201, [], "{}"}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Bot.perform_issue(issue, %{owner: "foo", repo: "bar"}) == :ok
        end)

      assert log =~ "Closed expired job"
    end
  end
end
