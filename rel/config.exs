~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
    # This sets the default release built by `mix release`
    default_release: :default,
    # This sets the default environment used by `mix release`
    default_environment: Mix.env()

environment :dev do
  set dev_mode: true
  set include_erts: false
  set cookie: :job_board
end

environment :prod do
  set include_erts: true
  set include_src: false
  set cookie: :crypto.strong_rand_bytes(32) |> Base.url_encode64() |> String.to_atom()
  set vm_args: "rel/vm.args"
end

release :job_board do
  set version: current_version(:job_board)
  set applications: []
end

