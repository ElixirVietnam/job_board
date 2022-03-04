defmodule JobBoard.Bot do
  alias JobBoard.Github

  require Logger

  @enforce_keys [:interval, :repo]
  defstruct @enforce_keys

  def perform(repo) do
    repo
    |> Github.stream_issues()
    |> Stream.flat_map(& &1)
    |> Task.async_stream(&perform_issue(&1, repo))
    |> Stream.run()
  end

  def perform_issue(issue, repo) do
    %{"title" => title, "number" => number, "labels" => labels} = issue

    cond do
      expired?(issue) ->
        payload = %{
          state: "closed",
          labels: ["Expired"]
        }

        with {:ok, _issue} <- Github.update_issue(repo, number, payload),
             closing_comment =
               ":robot: Closing this job post because it has been expired :alarm_clock:.",
             {:ok, _comment} <- Github.create_comment(repo, number, closing_comment) do
          Logger.debug("Closed expired job", issue_number: Integer.to_string(number))
        end

      maybe_from_agency?(issue) ->
        payload = %{
          state: "closed",
          labels: ["Maybe Agency"]
        }

        with {:ok, _issue} <- Github.update_issue(repo, number, payload),
             closing_comment = """
             Thank you for posting! We see that you are using personal emails for contact info. Currently we do not accept jobs from head-hunters or agencies for the sake of the high quality of the job board.

             In case of misunderstanding, please help to clarify with a comment. This post will remain closed until the concern is fully addressed.

             Thank you and have a good day!
             """,
             {:ok, _comment} <- Github.create_comment(repo, number, closing_comment) do
          Logger.debug("Closed job because it might be from agencies",
            issue_number: Integer.to_string(number)
          )
        end

        :ok

      written_in_vietnamese?(issue) ->
        payload = %{
          state: "closed",
          labels: ["invalid"]
        }

        with {:ok, _issue} <- Github.update_issue(repo, number, payload),
             closing_comment = """
             Thank you for posting! Unfortunately, we require job posts to be written in English.

             In case of misunderstanding, please help to clarify with a comment. This post will remain closed until the concern is fully addressed.

             Thank you and have a good day!
             """,
             {:ok, _comment} <- Github.create_comment(repo, number, closing_comment) do
          Logger.debug("Closed job because it is written in Vietnamese",
            issue_number: Integer.to_string(number)
          )
        end

        :ok

      true ->
        existing_labels = labels |> Enum.map(& &1["name"]) |> MapSet.new()
        labels = determine_labels(existing_labels, title)

        if labels != existing_labels do
          payload = %{
            labels: MapSet.to_list(labels)
          }

          with {:ok, _} <- Github.update_issue(repo, number, payload) do
            Logger.debug("Added labels to issue: #{inspect(labels)}", issue_number: number)
          end
        end

        :ok
    end
  end

  defp determine_labels(labels, title) do
    case title |> String.downcase() |> String.split(" - ", parts: 4) do
      [_company_name, position, location, type] ->
        labels
        |> determine_labels_from_position(String.trim(position))
        |> determine_labels_from_location(String.trim(location))
        |> determine_labels_from_type(String.trim(type))

      _other ->
        labels
    end
  end

  @technology_labels [
    {"javascript", "Lang:JavaScript"},
    {"java", "Lang:Java"},
    {"elixir", "Lang:Elixir"},
    {"js", "Lang:JavaScript"},
    {"react", "Lang:JavaScript"},
    {"c++", "Lang:C++"},
    {"c#", "Lang:DotNet"},
    {".net", "Lang:DotNet"},
    {"go", "Lang:Go"},
    {"ruby", "Lang:Ruby"},
    {"rails", "Lang:Ruby"},
    {"php", "Lang:PHP"},
    {"python", "Lang:Python"},
    {"data engineer", "Data Engineer"},
    {"data scientist", "Data Engineer"},
    {"scala", "Lang:Scala"},
    {"android", "Android"},
    {"ios", "iOS"},
    {"devops", "DevOps"},
    {"qa", "Quality Control"},
    {"qc", "Quality Control"},
    {"senior", "Senior"},
    {"junior", "Junior"},
    {"intern", "Intern"}
  ]

  defp determine_labels_from_position(labels, position) do
    {_, labels} =
      Enum.reduce(@technology_labels, {position, labels}, fn {pattern, label}, {position, acc} ->
        put_if_contains(acc, position, pattern, label)
      end)

    labels
  end

  @location_labels [
    {"sai gon", "Saigon"},
    {"saigon", "Saigon"},
    {"hcm", "Saigon"},
    {"ho chi minh", "Saigon"},
    {"tphcm", "Saigon"},
    {"hn", "Hanoi"},
    {"hanoi", "Hanoi"},
    {"ha noi", "Hanoi"},
    {"da nang", "Danang"},
    {"danang", "Danang"},
    {"dn", "Danang"},
    {"remote", "Remote"}
  ]

  defp determine_labels_from_location(labels, location) do
    {_, labels} =
      Enum.reduce(@location_labels, {location, labels}, fn {pattern, label}, {location, acc} ->
        put_if_contains(acc, location, pattern, label)
      end)

    labels
  end

  defp determine_labels_from_type(labels, type) do
    case type do
      "ft" -> MapSet.put(labels, "Full-time")
      "pt" -> MapSet.put(labels, "Part-time")
      "c" -> MapSet.put(labels, "Contract")
      _other -> labels
    end
  end

  defp put_if_contains(labels, string, pattern, label) do
    if String.contains?(string, pattern) do
      {String.replace(string, pattern, ""), MapSet.put(labels, label)}
    else
      {string, labels}
    end
  end

  defp expired?(%{"created_at" => created_at}) do
    created_at = NaiveDateTime.from_iso8601!(created_at)

    expiry_threshold = _100_days = 100 * 24 * 60 * 60

    NaiveDateTime.diff(NaiveDateTime.utc_now(), created_at) > expiry_threshold
  end

  @authorized_users []

  defp maybe_from_agency?(%{"body" => body, "labels" => labels, "user" => %{"login" => login}}) do
    label_names = Enum.map(labels, &Map.fetch!(&1, "name"))

    "Authorized" not in label_names and
      login not in @authorized_users and
      String.contains?(body, "@gmail.com")
  end

  @vietnamese_keywords ["lương", "cạnh tranh", "thưởng", "lập trình"]

  defp written_in_vietnamese?(%{"body" => body}) do
    body
    |> String.normalize(:nfc)
    |> String.contains?(@vietnamese_keywords)
  end
end
