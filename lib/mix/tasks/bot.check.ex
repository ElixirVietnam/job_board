defmodule Mix.Tasks.Bot.Check do
  use Mix.Task

  def run(_args) do
    {:ok, _} =
      Supervisor.start_link(
        [JobBoard.HTTPClient.Standard],
        strategy: :one_for_one
      )

    JobBoard.Bot.perform("awesome-jobs/vietnam")
  end
end
