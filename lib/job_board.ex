defmodule JobBoard do
  use Application

  def start(_type, _args) do
    children = [
      JobBoard.Github
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
