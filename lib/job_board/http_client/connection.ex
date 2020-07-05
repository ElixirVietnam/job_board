defmodule JobBoard.HTTPClient.Connection do
  use Connection

  require Logger

  defstruct [:endpoint_uri, :conn, request: %{}]

  def start_link(endpoint) when is_binary(endpoint) do
    Connection.start_link(__MODULE__, URI.parse(endpoint))
  end

  def request(pid, method, path, headers, body) do
    Connection.call(pid, {:request, method, path, headers, body})
  end

  @impl true
  def init(endpoint_uri) do
    {:connect, :init, %__MODULE__{endpoint_uri: endpoint_uri}}
  end

  @impl true
  def connect(_info, state) do
    case connect(state.endpoint_uri) do
      {:ok, conn} ->
        {:ok, %{state | conn: conn}}

      {:error, :invalid_uri} ->
        {:stop, :invalid_uri, state}

      {:error, _reason} ->
        {:backoff, 1_000, state}
    end
  end

  defp connect(%URI{scheme: "https", host: host, port: port} = uri) do
    Logger.debug(["Connecting to ", inspect(uri)])
    Mint.HTTP.connect(:https, host, port)
  end

  defp connect(_), do: {:error, :invalid_uri}

  @impl true
  def disconnect(_info, state) do
    Logger.debug(["Disconnecting from remote peer ", inspect(state.endpoint_uri)])
    {:ok, _conn} = Mint.HTTP.close(state.conn)

    state = %{state | conn: nil, request: %{}}
    {:connect, :reconnect, state}
  end

  @impl true
  def handle_call({:request, method, path, headers, body}, from, state) do
    case Mint.HTTP.request(state.conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = %{state | conn: conn}
        state = put_in(state.request, %{from: from, ref: request_ref})

        {:noreply, state}

      {:error, _, reason} ->
        {:disconnect, :request_failure, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.HTTP.stream(state.conn, message) do
      :unknown ->
        _ = Logger.error(fn -> "Received unknown message: " <> inspect(message) end)
        {:disconnect, :unknown_message, state}

      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &process_response/2)
        {:noreply, state}

      {:error, _conn, error, _} ->
        {:disconnect, error, state}
    end
  end

  defp process_response({:status, request_ref, status}, %{request: %{ref: request_ref}} = state) do
    put_in(state.request[:status], status)
  end

  defp process_response({:headers, request_ref, headers}, %{request: %{ref: request_ref}} = state) do
    put_in(state.request[:headers], headers)
  end

  defp process_response({:data, request_ref, new_data}, %{request: %{ref: request_ref}} = state) do
    update_in(state.request[:data], fn data -> (data || "") <> new_data end)
  end

  defp process_response({:done, request_ref}, %{request: %{from: from, ref: request_ref} = request} = state) do
    %{status: status, headers: headers, data: data} = request

    GenServer.reply(from, {:ok, status, headers, data})
    %{state | request: %{}}
  end
end
