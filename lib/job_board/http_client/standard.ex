defmodule JobBoard.HTTPClient.Standard do
  @behaviour JobBoard.HTTPClient

  @hackney_pool :standard

  def child_spec([]) do
    :hackney_pool.child_spec(@hackney_pool, timeout: 15_000, max_connections: 5)
  end

  def request(method, url, headers, body, options) do
    :hackney.request(method, url, headers, body, [:with_body, pool: @hackney_pool] ++ options)
  end
end
