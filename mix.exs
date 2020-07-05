defmodule JobBoard.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project() do
    [
      app: :job_board,
      version: @version,
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      xref: [
        exclude: [
          JobBoard.HTTPClient.Mock
        ]
      ]
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
      {:castore, "~> 0.1"},
      {:mint, "~> 1.1"},
      {:poolboy, "~> 1.5"},
      {:connection, "~> 1.0"},
      {:jason, "~> 1.1"},
      {:dicon, "~> 0.5.0", runtime: false},
      {:distillery, "~> 2.0", runtime: false},
      {:mox, "~> 0.5", only: :test}
    ]
  end

  defp aliases() do
    [test: ["test --no-start"]]
  end
end
