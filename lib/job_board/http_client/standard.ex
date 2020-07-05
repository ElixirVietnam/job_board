defmodule JobBoard.HTTPClient.Standard do
  @behaviour JobBoard.HTTPClient

  @pool_name :mint_pool

  @pool_config [
    name: {:local, @pool_name},
    worker_module: JobBoard.HTTPClient.Connection,
    size: 5,
    max_overflow: 1
  ]

  @worker_config "https://api.github.com"

  def child_spec([]) do
    :poolboy.child_spec(:worker, @pool_config, @worker_config)
  end

  def request(method, path, headers, body) do
    path = IO.iodata_to_binary(path)
    method = normalize_method(method)

    :poolboy.transaction(
      @pool_name,
      &JobBoard.HTTPClient.Connection.request(&1, method, path, headers, body)
    )
  end

  def normalize_method(method) when method in [:get, :post, :put, :patch, :delete] do
    method |> Atom.to_string() |> String.upcase()
  end
end
