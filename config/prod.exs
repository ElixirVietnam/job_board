use Mix.Config

config :job_board, JobBoard.Github,
  username: {:system, "GH_USERNAME"},
  access_token: {:system, "GH_ACCESS_TOKEN"}
