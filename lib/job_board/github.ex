defmodule JobBoard.Github do
  require Logger

  @http_client Application.get_env(:job_board, :http_client, JobBoard.HTTPClient.Standard)
  @config Application.fetch_env!(:job_board, __MODULE__)

  def stream_issues(owner, repo) do
    Stream.unfold(1, fn page ->
      if page do
        case list_issues(owner, repo, page) do
          {:ok, issues, true} -> {issues, page + 1}
          {:ok, issues, false} -> {issues, nil}
          :error -> nil
        end
      end
    end)
  end

  defp list_issues(owner, repo, page) when page > 0 do
    query_string = URI.encode_query(%{page: page})

    req_url = ["https://api.github.com/repos/", owner, ?/, repo, "/issues", ?? | query_string]

    req_headers = [{"accept", "application/json"}]

    case @http_client.request(:get, req_url, req_headers, [], build_req_options()) do
      {:ok, 200, resp_headers, resp_body} ->
        case Jason.decode(resp_body) do
          {:ok, payload} ->
            {:ok, payload, has_next_page?(resp_headers)}

          {:error, _reason} ->
            Logger.error("Could not decode response body: " <> inspect(resp_body))
            :error
        end

      {:ok, status, _resp_headers, resp_body} ->
        Logger.error(
          "Received unexpected response, status code: " <>
            inspect(status) <>
            ", body: " <> inspect(resp_body)
        )

        :error

      {:error, reason} ->
        Logger.error("Could not reach Github API, reason: " <> inspect(reason))

        :error
    end
  end

  defp has_next_page?(headers) do
    Enum.any?(headers, fn {key, value} ->
      key == "Link" and String.contains?(value, ~s(rel="next"))
    end)
  end

  def update_issue(owner, repo, issue_id, payload)
      when is_number(issue_id) and is_map(payload) do
    req_url = [
      "https://api.github.com/repos/",
      owner,
      ?/,
      repo,
      "/issues/",
      Integer.to_string(issue_id)
    ]

    req_headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    req_body = Jason.encode_to_iodata!(payload)

    case @http_client.request(:patch, req_url, req_headers, req_body, build_req_options()) do
      {:ok, 200, _resp_headers, resp_body} ->
        with {:error, _reason} <- Jason.decode(resp_body) do
          Logger.error("Could not decode response body: " <> inspect(resp_body))
          :error
        end

      {:ok, status, _resp_headers, resp_body} ->
        Logger.error(
          "Received unexpected response, status code: " <>
            inspect(status) <>
            ", body: " <> inspect(resp_body)
        )

        :error

      {:error, reason} ->
        Logger.error("Could not reach Github API, reason: " <> inspect(reason))

        :error
    end
  end

  def create_comment(owner, repo, issue_id, comment_body)
      when is_number(issue_id) and is_binary(comment_body) do
    req_url = [
      "https://api.github.com/repos/",
      owner,
      ?/,
      repo,
      "/issues/",
      Integer.to_string(issue_id),
      "/comments"
    ]

    req_headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    req_body = Jason.encode_to_iodata!(%{body: comment_body})

    case @http_client.request(:post, req_url, req_headers, req_body, build_req_options()) do
      {:ok, 201, _resp_headers, resp_body} ->
        with {:error, _reason} <- Jason.decode(resp_body) do
          Logger.error("Could not decode response body: " <> inspect(resp_body))
          :error
        end

      {:ok, status, _resp_headers, resp_body} ->
        Logger.error(
          "Received unexpected response, status code: " <>
            inspect(status) <>
            ", body: " <> inspect(resp_body)
        )

        :error

      {:error, reason} ->
        Logger.error("Could not reach Github API, reason: " <> inspect(reason))

        :error
    end
  end

  defp build_req_options() do
    [
      basic_auth: {
        fetch_option(@config, :username),
        fetch_option(@config, :access_token)
      }
    ]
  end

  defp fetch_option(options, name) do
    case Keyword.fetch(options, name) do
      {:ok, option} ->
        case option do
          {:system, env_var} ->
            System.get_env(env_var) || raise "#{inspect(name)} option is expected to be set"

          value ->
            value
        end

      :error ->
        raise "#{inspect(name)} option is expected to be set"
    end
  end
end
