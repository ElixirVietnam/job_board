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
    "body" => "Dummy body",
    "user" => %{"login" => "foo"},
    "created_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
  }

  describe "perform_issue/2" do
    test "closes the issue if it is expired" do
      created_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-101 * 24 * 60 * 60)
        |> NaiveDateTime.to_iso8601()

      issue = %{@issue | "created_at" => created_at}

      expect(HTTPClient.Mock, :request, fn :patch, req_path, _, req_body ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1"

        assert Jason.decode!(req_body) == %{
                 "labels" => ["Expired"],
                 "state" => "closed"
               }

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      expect(HTTPClient.Mock, :request, fn :post, req_path, _, _ ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1/comments"

        {:ok, 201, [], "{}"}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
        end)

      assert log =~ "Closed expired job"
    end

    defp assert_putting_label(issue, label) do
      expect(HTTPClient.Mock, :request, fn :patch, req_path, _, req_body ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1"

        assert %{"labels" => labels} = Jason.decode!(req_body)

        assert label in labels

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
        end)

      assert log =~ "Added labels to issue"
    end

    defp assert_not_putting_label(issue, label) do
      expect(HTTPClient.Mock, :request, fn :patch, req_path, _, req_body ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1"

        assert %{"labels" => labels} = Jason.decode!(req_body)

        assert label not in labels

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
        end)

      assert log =~ "Added labels to issue"
    end

    test "adds location label to issue accordingly" do
      locations = [
        {"HCM", "Saigon"},
        {"Sai Gon", "Saigon"},
        {"Ha Noi", "Hanoi"},
        {"HN", "Hanoi"},
        {"hn", "Hanoi"},
        {"Da nang", "Danang"},
        {"DN", "Danang"},
        {"Remote", "Remote"}
      ]

      for {location_text, location_label} <- locations do
        issue = %{@issue | "title" => "A - Ruby on Rails developer - #{location_text} - FT"}

        assert_putting_label(issue, location_label)
      end
    end

    test "adds language label to issue accordingly" do
      languages = [
        {"Ruby on Rails developer", "Lang:Ruby"},
        {"javascript developer", "Lang:JavaScript"},
        {"NodeJS developer", "Lang:JavaScript"},
        {"Golang engineer", "Lang:Go"},
        {"Backend engineer (Scala)", "Lang:Scala"},
        {".NET developer", "Lang:DotNet"},
        {"03 Data engineer", "Data Engineer"},
        {"QA Engineer", "Quality Control"},
        {"QC/QA", "Quality Control"},
        {"DevOps engineer", "DevOps"}
      ]

      for {language_text, language_label} <- languages do
        issue = %{@issue | "title" => "A - #{language_text} - Hanoi - FT"}

        assert_putting_label(issue, language_label)
      end
    end

    test "does not add wrong language label to issue" do
      languages = [
        {"javascript developer", "Lang:Java"}
      ]

      for {language_text, language_label} <- languages do
        issue = %{@issue | "title" => "A - #{language_text} - Hanoi - FT"}

        assert_not_putting_label(issue, language_label)
      end
    end

    test "adds level label to issue accordingly" do
      levels = [
        {"Senior Backend Developer", "Senior"},
        {"Junior front-end engineer", "Junior"},
        {"03 Intern to work on very interesting project", "Intern"}
      ]

      for {level_text, level_label} <- levels do
        issue = %{@issue | "title" => "A - #{level_text} - Hanoi - FT"}

        assert_putting_label(issue, level_label)
      end
    end

    test "adds contract type label to issue accordingly" do
      contract_types = [
        {"FT", "Full-time"},
        {"PT", "Part-time"},
        {"C", "Contract"}
      ]

      for {contract_type_text, contract_type_label} <- contract_types do
        issue = %{@issue | "title" => "A - Engineer - Hanoi - #{contract_type_text}"}

        assert_putting_label(issue, contract_type_label)
      end
    end

    test "keeps existing labels" do
      issue = %{
        @issue
        | "labels" => [%{"name" => "Foo"}, %{"name" => "Bar"}],
          "title" => "A - B - C - FT"
      }

      expect(HTTPClient.Mock, :request, fn :patch, req_path, _, req_body ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1"

        assert %{"labels" => labels} = Jason.decode!(req_body)

        assert "Foo" in labels
        assert "Bar" in labels

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
      end)
    end

    test "skips making requests if labels have not changed" do
      issue = %{
        @issue
        | "labels" => [%{"name" => "Foo"}, %{"name" => "Bar"}],
          "title" => "Random title"
      }

      assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
    end

    test "closes job posts that might be from agency" do
      issue = %{@issue | "body" => "Email: foo@gmail.com"}

      expect(HTTPClient.Mock, :request, fn :patch, req_path, _, req_body ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1"

        assert Jason.decode!(req_body) == %{
                 "labels" => ["Maybe Agency"],
                 "state" => "closed"
               }

        {:ok, 200, [], Jason.encode!(issue)}
      end)

      expect(HTTPClient.Mock, :request, fn :post, req_path, _, _ ->
        assert IO.iodata_to_binary(req_path) == "/repos/foo/bar/issues/1/comments"

        {:ok, 201, [], "{}"}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Bot.perform_issue(issue, %{repo: "foo/bar"}) == :ok
        end)

      assert log =~ "Closed job because it might be from agencies"
    end
  end
end
