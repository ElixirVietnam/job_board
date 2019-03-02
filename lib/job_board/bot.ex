defmodule JobBoard.Bot do
  use GenServer

  alias JobBoard.Github

  require Logger

  @enforce_keys [:interval, :owner, :repo]
  defstruct @enforce_keys

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def init(options) do
    schedule_perform(0)

    with {:ok, owner} <- fetch_option(options, :owner),
         {:ok, repo} <- fetch_option(options, :repo),
         {:ok, interval} <- fetch_option(options, :interval) do
      state = %__MODULE__{
        interval: interval,
        repo: repo,
        owner: owner
      }

      {:ok, state}
    else
      :error -> {:stop, :missing_required_option}
    end
  end

  def handle_info(:perform, state) do
    schedule_perform(state.interval)

    state.owner
    |> Github.stream_issues(state.repo)
    |> Stream.flat_map(& &1)
    |> Task.async_stream(&perform_issue(&1, state))
    |> Stream.run()

    Logger.debug("Finished performing")

    {:noreply, state}
  end

  def perform_issue(issue, %{owner: owner, repo: repo}) do
    %{"title" => title, "number" => number, "labels" => labels} = issue

    if expired?(issue) do
      payload = %{
        state: "closed",
        labels: ["Expired"]
      }

      with {:ok, _issue} <- Github.update_issue(owner, repo, number, payload),
           closing_comment =
             ":robot: Closing this job post because it has been expired :alarm_clock:.",
           {:ok, _comment} <- Github.create_comment(owner, repo, number, closing_comment) do
        Logger.debug("Closed expired job", issue_number: Integer.to_string(number))
      end
    else
      existing_labels = labels |> Enum.map(& &1["name"]) |> MapSet.new()
      labels = compute_labels(existing_labels, title)

      if labels != existing_labels do
        payload = %{
          labels: MapSet.to_list(labels)
        }

        with {:ok, _} <- Github.update_issue(owner, repo, number, payload) do
          Logger.debug("Added labels to issue: #{inspect(labels)}", issue_number: number)
        end
      end

      :ok
    end
  end

  defp compute_labels(labels, title) do
    case title |> String.downcase() |> String.split(" - ", parts: 4) do
      [_company_name, position, location, type] ->
        labels
        |> compute_labels_from_position(String.trim(position))
        |> compute_labels_from_location(String.trim(location))
        |> compute_labels_from_type(String.trim(type))

      _other ->
        labels
    end
  end

  defp compute_labels_from_position(labels, position) do
    labels
    |> put_if_contains(position, "java", "Lang:Java")
    |> put_if_contains(position, "elixir", "Lang:Elixir")
    |> put_if_contains(position, "javascript", "Lang:JavaScript")
    |> put_if_contains(position, "js", "Lang:JavaScript")
    |> put_if_contains(position, "react", "Lang:JavaScript")
    |> put_if_contains(position, "c++", "Lang:C++")
    |> put_if_contains(position, "c#", "Lang:DotNet")
    |> put_if_contains(position, ".net", "Lang:DotNet")
    |> put_if_contains(position, "go", "Lang:Go")
    |> put_if_contains(position, "ruby", "Lang:Ruby")
    |> put_if_contains(position, "rails", "Lang:Ruby")
    |> put_if_contains(position, "php", "Lang:PHP")
    |> put_if_contains(position, "python", "Lang:Python")
    |> put_if_contains(position, "data engineer", "Data Engineer")
    |> put_if_contains(position, "data scientist", "Data Engineer")
    |> put_if_contains(position, "scala", "Lang:Scala")
    |> put_if_contains(position, "android", "Android")
    |> put_if_contains(position, "ios", "iOS")
    |> put_if_contains(position, "devops", "DevOps")
    |> put_if_contains(position, "qa", "Quality Control")
    |> put_if_contains(position, "qc", "Quality Control")
    |> put_if_contains(position, "senior", "Senior")
    |> put_if_contains(position, "junior", "Junior")
    |> put_if_contains(position, "intern", "Intern")
  end

  defp compute_labels_from_location(labels, location) do
    labels
    |> put_if_contains(location, "sai gon", "Saigon")
    |> put_if_contains(location, "saigon", "Saigon")
    |> put_if_contains(location, "hcm", "Saigon")
    |> put_if_contains(location, "hn", "Hanoi")
    |> put_if_contains(location, "hanoi", "Hanoi")
    |> put_if_contains(location, "ha noi", "Hanoi")
    |> put_if_contains(location, "da nang", "Danang")
    |> put_if_contains(location, "danang", "Danang")
    |> put_if_contains(location, "dn", "Danang")
    |> put_if_contains(location, "remote", "Remote")
  end

  defp compute_labels_from_type(labels, type) do
    case type do
      "ft" -> MapSet.put(labels, "Full-time")
      "pt" -> MapSet.put(labels, "Part-time")
      "c" -> MapSet.put(labels, "Contract")
      _other -> labels
    end
  end

  defp put_if_contains(labels, position, keyword, label) do
    if String.contains?(position, keyword), do: MapSet.put(labels, label), else: labels
  end

  defp expired?(%{"created_at" => created_at}) do
    created_at = NaiveDateTime.from_iso8601!(created_at)

    expiry_threshold = _100_days = 100 * 24 * 60 * 60

    NaiveDateTime.diff(NaiveDateTime.utc_now(), created_at) > expiry_threshold
  end

  defp schedule_perform(interval) do
    Process.send_after(self(), :perform, interval)
  end

  defp fetch_option(options, name) do
    with {:ok, option} <- Keyword.fetch(options, name) do
      if value = get_option_value(option),
        do: {:ok, value},
        else: :error
    end
  end

  defp get_option_value({:system, env_var}), do: System.get_env(env_var)
  defp get_option_value(value), do: value
end
