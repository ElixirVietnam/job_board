defmodule JobBoard.MixProject do
  use Mix.Project

  def project() do
    [
      app: :job_board,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application() do
    [
      mod: {JobBoard, []},
      extra_applications: [:logger]
    ]
  end

  defp deps() do
    [
      {:hackney, "== 1.6.5"},
      {:jason, "~> 1.1"}
    ]
  end
end
