defmodule JobBoard do
  use Application

  def start(_type, _args) do
    bot_options =
      :job_board
      |> Application.get_env(JobBoard.Bot, [])
      |> Keyword.put_new(:interval, _15_minutes = 90_000)

    children = [
      JobBoard.Github,
      {JobBoard.Bot, bot_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
