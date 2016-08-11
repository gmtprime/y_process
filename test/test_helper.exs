ExUnit.start()

defmodule EvalYProcess do
  use YProcess

  def init(fun) when is_function(fun, 0), do: fun.()
  def init(state), do: {:ok, state}

  def ready(action, channels, pid) when is_pid(pid) do
    send pid, {:ready, action, channels}
    {:noreply, pid}
  end
  def ready(_action, _channels, state) do
    {:noreply, state}
  end

  def handle_call(:state, _from, state), do:
    {:reply, state, state}
  def handle_call(fun, from, state) when is_function(fun), do:
    fun.(from, state)
  def handle_call(message, from, fun) when is_function(fun), do:
    fun.(message, from, fun)

  def handle_cast(fun, state), do: fun.(state)

  def handle_event(channel, message, fun), do: fun.(channel, message)

  def handle_info(message, state) when is_function(message, 1), do:
    message.(state)
  def handle_info(message, fun) when is_function(fun, 1), do:
    fun.(message)
  def handle_info(message, fun) when is_function(fun, 2), do:
    fun.(message, fun)
end

defmodule EvalBackend do
  use YProcess.Backend
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, nil, [])
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def create(channel) do
    {server, channel} = channel
    GenServer.call(server, {:create, channel})
  end

  def delete(channel) do
    {server, channel} = channel
    GenServer.call(server, {:delete, channel})
  end

  def join(channel, pid) do
    {server, channel} = channel
    GenServer.call(server, {:join, channel, pid})
  end

  def leave(channel, pid) do
    {server, channel} = channel
    GenServer.call(server, {:leave, channel, pid})
  end

  def emit(channel, message) do
    {server, channel} = channel
    GenServer.call(server, {:emit, channel, message})
  end

  def state(server) do
    GenServer.call(server, :state)
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end
  def handle_call({:create, channel}, _from, state) do
    case Map.get(state, channel) do
      nil ->
        new_state = Map.put(state, channel, [])
        {:reply, :ok, new_state}
      _ ->
        {:reply, :ok, state}
    end
  end
  def handle_call({:delete, channel}, _from, state) do
    case Map.get(state, channel) do
      nil ->
        {:reply, :ok, state}
      _ ->
        new_state = Map.delete(state, channel)
        {:reply, :ok, new_state}
    end
  end
  def handle_call({:join, channel, pid}, _from, state) do
    case Map.get(state, channel) do
      nil ->
        new_state = Map.put(state, channel, [pid])
        {:reply, :ok, new_state}
      pids ->
        new_state = Map.put(state, channel, [pid | pids])
        {:reply, :ok, new_state}
    end
  end
  def handle_call({:leave, channel, pid}, _from, state) do
    case Map.get(state, channel) do
      nil ->
        {:reply, :ok, state}
      pids ->
        if pid in pids do
          new_state = Map.put(state, channel, List.delete(pids, pid))
          {:reply, :ok, new_state}
        else
          {:reply, :ok, state}
        end
    end
  end
  def handle_call({:emit, channel, message}, _from, state) do
    case Map.get(state, channel) do
      nil ->
        {:reply, :error, state}
      pids ->
        Enum.map(pids, &(send(&1, message)))
        {:reply, :ok, state}
    end
  end
  def handle_call(_, _, state) do
    {:reply, :not_implemented, state}
  end
end
