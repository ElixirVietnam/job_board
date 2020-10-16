use Mix.Config

config :job_board, JobBoard.Github, username: "foo", access_token: "bar"

config :job_board, JobBoard.Bot, repo: "foo/bar"

config :job_board, :http_client, JobBoard.HTTPClient.Mock
