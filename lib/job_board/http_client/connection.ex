defmodule JobBoard.HTTPClient.Connection do
  use Connection

  require Logger

  defstruct [:endpoint_uri, :conn, :ref, request: %{}]

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
    Logger.debug(["Connecting to remote server: ", inspect(uri)])
    Mint.HTTP.connect(:https, host, port)
  end

  defp connect(_), do: {:error, :invalid_uri}

  @impl true
  def disconnect(_info, %__MODULE__{endpoint_uri: endpoint_uri, conn: conn}) do
    {:ok, _conn} = Mint.HTTP.close(conn)
    state = %__MODULE__{endpoint_uri: endpoint_uri}
    {:connect, :reconnect, state}
  end

  @impl true
  def handle_call({:request, method, path, headers, body}, from, %{ref: nil} = state) do
    case Mint.HTTP.request(state.conn, method, path, headers, body) do
      {:ok, conn, request_ref} ->
        state = %{state | conn: conn, ref: request_ref, request: %{from: from}}
        {:noreply, state}

      {:error, _, reason} ->
        {:disconnect, :request_failure, {:error, reason}, state}
    end
  end

  # There is an on-going request and we do not support HTTP pipelining.
  def handle_call({:request, _method, _path, _headers, _body}, _from, %{ref: _ref} = state) do
    {:reply, {:error, :unsupported}, state}
  end

  @impl true
  def handle_info(message, state) do
    case Mint.HTTP.stream(state.conn, message) do
      :unknown ->
        Logger.error(["Received unknown message: ", inspect(message)])
        {:disconnect, :unknown_message, state}

      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &process_response/2)
        {:noreply, state}

      {:error, _conn, error, _} ->
        case error do
          %Mint.TransportError{reason: reason} ->
            {:disconnect, reason, state}

          _ ->
            Logger.warn(["Received erroneous response: ", inspect(error)])
            {:disconnect, :response_failure, state}
        end
    end
  end

  defp process_response({:status, request_ref, status}, %{ref: request_ref} = state) do
    Map.update!(state, :request, &Map.put(&1, :status, status))
  end

  defp process_response({:headers, request_ref, headers}, %{ref: request_ref} = state) do
    Map.update!(state, :request, &Map.put(&1, :headers, headers))
  end

  defp process_response({:data, request_ref, new_data}, %{ref: request_ref} = state) do
    update_in(state.request[:data], &[&1 || "" | new_data])
  end

  defp process_response(
         {:done, request_ref},
         %{ref: request_ref, request: %{from: from} = request} = state
       ) do
    %{status: status, headers: headers} = request
    data = request |> Map.get(:data, "") |> IO.iodata_to_binary()

    GenServer.reply(from, {:ok, status, headers, data})
    %{state | ref: nil, request: %{}}
  end
end
