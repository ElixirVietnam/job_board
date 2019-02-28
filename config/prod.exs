use Mix.Config

config :job_board, JobBoard.Github,
  username: {:system, "GITHUB_USERNAME"},
  access_token: {:system, "GITHUB_ACCESS_TOKEN"}

config :job_board, JobBoard.Bot,
  owner: {:system, "JOB_BOARD_OWNER"},
  repo: {:system, "JOB_BOARD_REPO"}
