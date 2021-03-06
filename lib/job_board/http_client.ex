defmodule JobBoard.HTTPClient do
  @callback request(
              method :: atom(),
              url :: iodata(),
              headers :: list(),
              body :: iodata()
            ) ::
              {:ok, status_code :: 100..599, headers :: list(), body :: binary()}
              | {:error, term()}
end
