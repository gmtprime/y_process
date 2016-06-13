defmodule YProcess do
  @moduledoc """
  # YProcess

  A behaviour module for implementing a server of a client-server relation with
  publisher-subscriber capabilities. This is a generalized implementation of a
  publisher subscriber using `:pg2` library using a `GenServer`.

  This project is heavily inspired by
  [`Connection`](https://github.com/fishcakez/connection).

  ## Solution using `:pg2`

      defmodule Consumer do
        def subscribe(channel, callback) do
          :pg2.join(channel, self)
          loop(channel, callback)
        end

        defp loop(channel, callback) do
          receive do
            :stop -> :stopped
            message ->
              try do
                callback.(message)
              catch
                _, _ -> :stopped
              else
               :ok -> loop(channel, callback)
               :stop -> :stopped
              end
          end
        end
      end

      defmodule Publisher do
        def create(channel) do
          :pg2.create(channel)
        end

        def publish(channel, message) do
          channel
           |> :pg2.get_members
           |> Enum.map(&(send(&1, message)))
          :ok
        end
      end

  When testing this modules in `iex`:

      iex(1)> Publisher.create("channel")
      :ok
      iex(2)> callback = fn message -> IO.inspect {self, message} end
      #Function<6.54118792/1 in :erl_eval.expr/5>
      iex(3)> spawn fn -> Consumer.subscribe("channel", callback) end
      #PID<0.168.0>
      iex(4)> spawn fn -> Consumer.subscribe("channel", callback) end
      #PID<0.170.0>
      iex(5)> Publisher.publish("channel", "hello")
      {#PID<0.168.0>, "hello"}
      {#PID<0.170.0>, "hello"}
      :ok
      iex(6)>

  If we wrap this around a `GenServer` we would have a better way to handle
  messages in the `Consumers`. Depending on the approach, the messages could be
  received either in `handle_call/3` (`GenServer.call/3`), `handle_cast/2`
  (`GenServer.cast/2`) or `handle_info/2` (`send/2`). `YProcess` wraps around
  `GenServer` behaviour adding a new callback: `handle_event/3` to handle the
  messages coming from the processes the current `YProcess` is subscribed.

  ## Callbacks

  There are seven callbacks required to be implemented in a `YProcess`. Six of
  them are the same as `GenServer` but with some other possible return values
  to join, leave, create, delete and emit messages (ackknowledged or not) to
  other processes. The seventh callback is `handle_event/3`. It should be used
  to handle the messages coming from other process if the current process is
  subscribed to the channel they are broadcasting the messages.

  ## Example

  Let's define a `Producer` that every second generates a number between 1 and
  10 and sends it to a `Consumer` that prints the number.

  So the `Producer` is as follows:

      defmodule Producer do
        use YProcess

        def start_link(channel) do
          YProcess.start_link(__MODULE__, channel)
        end

        def stop(producer) do
          YProcess.stop(producer)
        end

        defp get_number do
          (:random.uniform * 10) |> :erlang.trunc
        end

        def init(channel) do
          _ = :os.system_time(:seconds) |> :random.seed
          {:create, [channel], [channel], 1000}
        end

        def handle_info(:timeout, channels) do
          number = get_number
          {:emit, channels, number, channels, 1000}
        end
      end

  And the `Consumer` is as follows:

      defmodule Consumer do
        use YProcess

        def start_link(:channel) do
          YProcess.start_link(__MODULE__, :channel)
        end

        def stop(consumer) do
          YProcess.stop(consumer)
        end

        def init(channel) do
          {:join, [channel], channel}
        end

        def handle_event(channel, number, channel) when is_integer(number) do
          IO.puts inspect {self, number}
          {:noreply, channel}
        end
      end

  So when we start a `Producer` and several `Consumer`s we would have the
  following output:

      iex(1)> {:ok, producer} = Producer.start_link(:channel)
      {:ok, #PID<0.189.0>}
      iex(2)> {:ok, consumer0} = Consumer.start_link(:channel)
      {:ok, #PID<0.192.0>}
      {#PID<0.192.0>, 7}
      {#PID<0.192.0>, 8}
      iex(3)> {:ok, consumer1} = Consumer.start_link(:channel)
      {:ok, #PID<0.194.0>}
      {#PID<0.192.0>, 0}
      {#PID<0.194.0>, 0}
      {#PID<0.192.0>, 2}
      {#PID<0.194.0>, 2}
      {#PID<0.192.0>, 7}
      {#PID<0.194.0>, 7}
      iex(4)> Consumer.stop(consumer0)
      {#PID<0.194.0>, 2}
      {#PID<0.194.0>, 6}
      {#PID<0.194.0>, 1}
      iex(5)>

  ## Installation

  Add `YProcess` as a dependency in your `mix.exs` file.

      def deps do
          [{:y_process, "~> 0.0.1"}]
      end

  After you're done, run this in your shell to fetch the new dependency:

      $ mix deps.get
  """
  use Behaviour
  @behaviour :gen_server
  alias __MODULE__, as: YProcess

  @channel_header :"$Y_CHANNEL"
  @event_header :"$Y_EVENT"
  @deliver :"$Y_DELIVER"
  @no_deliver :"$Y_NODELIVER"

  @typedoc "Synchronous acked message timeout."
  @type ack_timeout :: timeout

  @typedoc "Channel. Shouldn't be a list."
  @type channel :: term

  @typedoc "List of channels."
  @type channels :: [channel]

  @typedoc "New message to be emitted by the `YProcess.`"
  @type new_message :: term

  @typedoc "New module state."
  @type new_state :: term

  @typedoc "Reply to the caller."
  @type reply :: term

  @typedoc "Synchronous callback response."
  @type sync_response ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:create, channels, reply, new_state} |
    {:create, channels, reply, new_state, timeout | :hibernate} |
    {:emit, channels, new_message, reply, new_state} |
    {:emit, channels, new_message, reply, new_state, timeout | :hibernate} |
    {:emit_ack, channels, new_message, ack_timeout, reply, new_state} |
    {:emit_ack, channels, new_message, ack_timeout, reply, new_state,
     timeout | :hibernate} |
    {:join, channels, reply, new_state} |
    {:join, channels, reply, new_state, timeout | :hibernate} |
    {:leave, channels, reply, new_state} |
    {:leave, channels, reply, new_state, timeout | :hibernate} |
    {:delete, channels, reply, new_state} |
    {:delete, channels, reply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, reply, new_state} |
    {:stop, reason :: term, new_state}

  @typedoc "Asynchronous callback response."
  @type async_response ::
    {:noreply, new_state, term} |
    {:noreply, new_state, timeout | :hibernate} |
    {:create, channels, new_state} |
    {:create, channels, new_state, timeout | :hibernate} |
    {:emit, channels, new_message, new_state} |
    {:emit, channels, new_message, new_state, timeout | :hibernate} |
    {:emit_ack, channels, new_message, ack_timeout, new_state} |
    {:emit_ack, channels, new_message, ack_timeout, new_state,
     timeout | :hibernate} |
    {:join, channels, new_state} |
    {:join, channels, new_state, timeout | :hibernate} |
    {:leave, channels, new_state} |
    {:leave, channels, new_state, timeout | :hibernate} |
    {:delete, channels, new_state} |
    {:delete, channels, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state}


  @doc """
  Invoked when the server is started. `start_link/3` (`start/3`) will block
  until it returns.

  `args` is the argument term (second argument) passed to `start_link/3`.

  Returning `{:ok, state}` will cause `start_link/3` to  return `{:ok, pid}`
  and the process to enter a loop.

  Returning `{:ok, state, timeout}` is similar to `{:ok, state}` except
  `handle_info(:timeout, state)` will be called after `timeout` milliseconds if
  no messages are received within the timeout.

  Returning `{:ok, state, :hibernate}` is similar to `{:ok, state}` except the
  process is hibernated before entering the loop. See `handle_call/3` for more
  information on hibernation.

  Returning `{:create, channels, state}` will create the channels listed in
  `channels` where every channel can be an arbitrary term.

  Returning `{:create, channels, state, timeout}` is similar to
  `{:create, channels, state}` except `handle_info(:timeout, state)` will be
  called after `timeout` milliseconds if no messages are received within the
  timeout.

  Returning `{:create, channels, state, :hibernate}` is similar to
  `{:create, channels, state}` except the process is hibernated before entering
  the loop. See `handle_call/3` for more information on hibernation.

  Returning `{:join, channels, state}` will subscribe to the channels
  listed in `channels` where every channel can be an arbitrary term.

  Returning `{:join, channels, state, timeout}` is similar to
  `{:join, channels, state}` except `handle_info(:timeout, state)` will be
  called after `timeout` milliseconds if no messages are received within the
  timeout.

  Returning `{:join, channels, state, :hibernate}` is similar to
  `{:join, channels, state}` except the process is hibernated before entering
  the loop. See `handle_call/3` for more information on hibernation.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the
  process will exit normally without entering the loop or calling
  `terminate/2`. If used when part of a supervision tree the parent supervisor
  will not fail to start not immediately try to restart the `YProcess`. The
  remainder of the supervision tree will be (re)started and so the `YProcess`
  should not be required by other processes. It can be restarted later with
  `Supervisor.restart_child/2` as the child specification is saved in the
  parent supervisor. The main use cases for this are:

  - The `YProcess` is disabled by configuration but might be enabled later.
  - An error occurred and it will be handled by a different mechanism than the
  `Supervisor`. Likely this approach involves calling
  `Supervisor.restart_child/2` after a delay to attempt a restart.

  Returning `{:stop, reason}` will cause `start_link/3` to return
  `{:error, reason}` and the process to exit with `reason` without entering the
  loop or calling `terminate/2`
  """
  @callback init(args :: term) ::
    {:ok, state} |
    {:ok, state, timeout | :hibernate} |
    {:create, channels, state} |
    {:create, channels, state, timeout | :hibernate} |
    {:join, channels, state} |
    {:join, channels, state, timeout | :hibernate} |
    :ignore |
    {:stop, reason :: any} when state: any, channels: list

  @doc """
  Invoked to handle synchronous `call/3` messages. `call/3` will block until a
  reply is received (unless the call times out or nodes are disconnected).

  `request` is the request message sent by a `call/3`, `from` is a 2-tuple
  containing the caller's pid and a term that uniquely identifies the call, and
  `state` is the current state of the `YProcess`.

  Returning `{:reply, reply, new_state}` send the response `reply` to the
  caller and continues the loop with new state `new_state`.

  Returning `{:reply, reply, new_state, timeout}` is similar to
  `{:reply, reply, new_state}` except `handle_info(:timeout, new_state)` will
  be called after `timeout` milliseconds if no messages are received.

  Returning `{:reply, reply, new_state, :hibernate}` is similar to
  `{:reply, reply, new_state}` except the process is hibernated and will
  continue the loop once a messages is in its message queue. If a message is
  already in the message queue this will immediately. Hibernating a `YProcess`
  causes garbage collection and leaves a continuous heap that minimises the
  memory used by the process.

  Hibernating should not be used aggressively as too much time could be spent
  garbage collecting. Normally, it should be only be used when a message is not
  expected soon and minimising the memory of the process is shown to be
  beneficial.

  Returning `{:noreply, new_state}` does not send a response to the caller and
  continues the loop with new_state `new_state`. The response must be sent with
  `reply/2`.

  There are three main use cases for not replying using the return value:

  - To reply before returning from the callback because the response is known
  before calling a slow function.
  - To reply after returning from the callback because the response is not yet
  available.
  - To reply from another process, such as a `Task`.

  Returning `{:noreply, new_state, timeout | :hibernate}` is similar to
  `{:noreply, new_state}` except a timeout or hibernation occurs as with a
  `:reply` tuple.

  Returning `{:create, channels, reply, new_state}` will create the `channels`
  and `reply` back to `call/3` caller.

  Returning `{:create, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:create, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:emit, channels, message, reply, new_state}` will emit a
  `message` in several `channels` while replying back to the `call/3` caller.
  The `YProcess` doesn't know whether the messages arrived to the subscribers
  or not.

  Returning
  `{:emit, channels, message, reply, new_state, timeout | :hibernate}`
  is similar to `{:emit, channels, message, new_state}` except a timeout
  or hibernation occurs as with the `:reply` tuple.

  Returning `{:emit_ack, channels, message, ack_timeout, reply, new_state}`
  will emit a `message` in several `channels` while sending a `reply` back to
  the `call/3` caller. The `YProcess` expects a confirmation from every
  subscriber in `handle_call/2`. The `ack_timeout` is the time the `Task` will
  wait for a response from the subscriber. The possible messages are that can
  be received in `handle_info/2` are `{:"$Y_DELIVER", channel, message, pid}`
  for delivered messages or `{:"$Y_NODELIVER", channel, message, pid}` for not
  deliveref messages.

  Returning
  `{:emit_ack, channels, message, ack_timeout, new_state, timeout | :hibernate}`
  is similar to `{:emit_ack, channels, message, ack_timeout, reply, new_state}`
  except a timeout or hibernation occurs as with the `:reply` tuple.

  Returning `{:join, channels, reply, new_state}` will join the `YProcess` to
  the `channels` and send a `reply` back to the `call/3` caller.

  Returning `{:join, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:join, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:leave, channels, reply, new_state}` the `YProcess` will leave the
  `channels` and send a `reply` back to the `call/3` caller.

  Returning `{:leave, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:leave, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:delete, channels, reply, new_state}` will delete the `channels`
  and `reply` back to `call/3` caller.

  Returning `{:delete, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:delete, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:stop, reason, reply, new_state}` stops the loop and
  `terminate/2` is called with reason `reason` and `new_state`. Then the
  `reply` is sent as response to the call and the process exist with `reason`.

  Returning `{:stop, reason, new_state}` is similar to
  `{:stop, reason, reply, new_state}` except a reply is not sent.
  """
  @callback handle_call(request :: term, from :: {pid, term}, state :: term) ::
    sync_response

  @doc """
  Invoked to handle asynchronous `cast/2` messages.

  `request` is the request message sent by a `cast/2` and `state` is the current
  state of the `YProcess`.

  The return values are similar to the ones in `handle_call/3` except the
  caller is not expecting a reply.
  """
  @callback handle_cast(request :: term, state :: term) :: async_response

  @doc """
  Invoked to handle all other messages.

  Receives the `message` and the current `YProcess` `state`. When a timeout
  occurs the message is `:timeout`.
  """
  @callback handle_info(message :: term | :timeout, state :: term) ::
    async_response

  @doc """
  Invoked to handle messages coming from a registered channel.

  `channel` is the channel from which the `message` is been received. `state`
  is the current state of the `YProcess`.
  """
  @callback handle_event(channel :: term, message :: term, state ::term) ::
    async_response

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.

  `reason` is the exit reason and `state` is the current state of the
  `YProcess`. The return value is ignored.

  `terminate/2` is called if a callback except `init/1` returns a `:stop`
  tuple, raises an exception, calls `Kernel.exit/1` or returns an invalid
  value. It may also be called if the `YProcess` traps exits using
  `Process.flag/2` *and* the parent process sends an exit signal.
  """
  @callback terminate(reason, state :: term) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term

  @doc """
  Invoked to change the state of the `YProcess` when a different version of a
  module is loaded (hot code swapping) and the state's term structure should be
  changed.

  `old_vsn` is the previous version of the module (defined by the `@vsn`
  attribute) when upgrading. When downgrading the previous version is wrapped
  in a 2-tuple with first element `:down`. `state` is the current state of the
  `YProcess` and `extra` is any extra data required to change the state.

  Returning `{:ok, state}` changes the state to `new_state` and code is changed
  succesfully.

  Returning `{:error, reason}` fails the code change with `reason` and the
  state remains as the previous state.

  If `code_change/3` raises an exception the code change fails and the loop
  will continue with its previous state. Therefore this callback does not
  usually contain side effects.
  """
  @callback code_change(old_vsn, state :: term, extra :: term) ::
    {:ok, new_state :: term} |
    {:error, reason :: term} when old_vsn: term | {:down, term}

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      @doc false
      def init(args), do: {:ok, args}

      @doc false
      def handle_call(message, _from, state) do
        reason = {:bad_call, message}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def handle_cast(message, state) do
        reason = {:bad_cast, message}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def handle_info(_message, state), do: {:noreply, state}

      @doc false
      def handle_event(channel, message, state) do
        reason = {:bad_event, {channel, message}}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def terminate(_reason, _state), do: :ok

      @doc false
      def code_change(_olv_vsn, state, _extra), do: {:ok, state}

      defoverridable [init: 1, handle_call: 3, handle_cast: 2, handle_info: 2,
                      handle_event: 3, terminate: 2, code_change: 3]
    end
  end

  @doc """
  Starts a `YProcess` process linked to the current process.

  This function is used to start a `YProcess` process in a supervision tree.
  The process will be started by calling `init/1` in the callback module with
  the given argument.

  This function will return after `init/1` has returned in the spawned process.
  The return values are controlled by the `init/1` callback.

  It receives the `module` where the callbacks are implemented, the arguments
  `args` that will receive `module.init/1` callback and the `options` for the
  `YProcess`. This `options` are the same expected by a `GenServer`.

  See `GenServer.start_link/3` for more information.
  """
  @spec start_link(module, any, GenServer.options) :: GenServer.on_start
  def start_link(module, args, options \\ [])
      when is_atom(module) and is_list(options) do
    start(module, args, options, :link)
  end

  @doc """
  Starts a `YProcess` process without links (outside of a supervision tree).

  It receives the `module` where the callbacks are implemented, the arguments
  `args` that will receive `module.init/1` callback and the `options` for the
  `YProcess`. This `options` are the same expected by a `GenServer`.

  See `start_link/3` for more information.
  """
  @spec start(module, any, GenServer.options) :: GenServer.on_start
  def start(module, args, options \\ [])
      when is_atom(module) and is_list(options) do
    start(module, args, options, :nolink)
  end

  @doc """
  Stops the `YProcess`.

  It receives the `name` or name of the server and optionally the  `reason` for
  termination (by default is `:normal`) and the `timeout` to wait for the
  termination.

  See `GenServer.stop/3` for more information.
  """
  @spec stop(name :: pid, reason :: term, timeout) :: :ok
  def stop(pid, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(pid, reason, timeout)
  end

  @doc """
  The current `YProcess` registers the `channels`. Must be called from any of
  the callbacks
  """
  @spec register_channel(channel :: list | term) :: :ok
  def register_channel(channels) when is_list(channels) do
    _ = create(channels)
    :ok
  end
  def register_channel(channel) do
    _ = create([channel])
    :ok
  end

  @doc """
  The current `YProcess` unregisters the `channels`. Must be called from any of
  the callbacks
  """
  @spec unregister_channel(channel :: list | term) :: :ok
  def unregister_channel(channels) when is_list(channels) do
      _ = delete(channels)
      :ok
  end
  def unregister_channel(channel) do
    _ = delete([channel])
    :ok
  end

  @doc """
  Subscribes a `YProcess` to one `channel` or many `channels`. Must be called
  from any of the `YProcess` callbacks.
  """
  @spec subscribe(channel :: list | term) :: :ok
  def subscribe(channels) when is_list(channels) do
    _ = join(channels)
    :ok
  end
  def subscribe(channel) do
    _ = join([channel])
    :ok
  end

  @doc """
  Unsubscribes a `YProcess` to one `channel` or many `channels`. Must be called
  from any of the `YProcess` callbacks.
  """
  @spec unsubscribe(channel :: list | term) :: :ok
  def unsubscribe(channels) when is_list(channels) do
    _ = leave(channels)
    :ok
  end
  def unsubscribe(channel) do
    _ = leave([channel])
    :ok
  end

  @doc """
  Publishes a `message` in one `channel` or many `channels`.
  """
  @spec publish(channel :: list | term, message :: term) :: :ok
  def publish(channels, message) when is_list(channels) do
    _ = emit(channels, message)
    :ok
  end
  def publish(channel, message) do
    _ = emit([channel], message)
    :ok
  end

  @doc """
  Publishes a `message` in one `channel` or many `channels`. Delivery
  confirmations are received asynchronously until `timeout` seconds. See
  `:emit_ack` response in `handle_call/3`.
  """
  @spec publish(channel :: list | term, message :: term, timeout) :: :ok
  def publish(channels, message, timeout) when is_list(channels) do
    _ = emit(channels, message, timeout)
    :ok
  end
  def publish(channel, message, timeout) do
    _ = emit([channel], message, timeout)
    :ok
  end

  @doc """
  Sends a reply to a request sent by `call/3`.

  It receives a `from` tuple and the `response` to a request.

  See `GenServer.reply/2` for more information.
  """
  defdelegate reply(from, response), to: :gen_server

  @doc """
  Sends a synchronous `request` to the `YProcess` process identified by `conn`
  and waits for a reply. Times out after `5000` milliseconds if no response is
  received.

  See `GenServer.call/2` for more information.
  """
  defdelegate call(conn, request), to: :gen_server

  @doc """
  Sends a synchronous `request` ot the `YProcess` process identified by `conn`
  and waits for a reply unless the call times out after `timeout` milliseconds.
  A possible value for `timeout` is `:infinity`. The call will block
  indefinitely.

  See `GenServer.call/3` for more information.
  """
  defdelegate call(conn, request, timeout), to: :gen_server

  @doc """
  Sends an asynchronous `request` to the `YProcess` process identified by
  `conn`.

  See `GenServer.cast/2` for more information.
  """
  defdelegate cast(conn, request), to: :gen_server

  defstruct [:module, :mod_state]

  #############################################################################
  # Callback definition.

  ##
  # Initializes the `GenServer`.
  @doc false
  def init_it(starter, _, name, module, args, opts) do
    # There is no init/1 defined, but this function simulates it.
    Process.put(:"$initial_call", {module, :init, 1})
    try do
      apply(module, :init, [args])
    catch
      :exit, reason ->
        init_stop(starter, name, reason)
      :error, reason ->
        init_stop(starter, name, {reason, System.stacktrace()})
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        init_stop(starter, name, reason)
    else
      {:ok, mod_state} ->
        init_ack(starter)
        enter_loop(module, mod_state, name, opts, :infinity)
      {:ok, mod_state, timeout} ->
        init_ack(starter)
        enter_loop(module, mod_state, name, opts, timeout)
      {:create, channels, mod_state} when is_list(channels) ->
        init_ack(starter)
        enter_create(module, mod_state, channels, name, opts, :infinity)
      {:create, channels, mod_state, timeout} when is_list(channels) ->
        init_ack(starter)
        enter_create(module, mod_state, channels, name, opts, timeout)
      {:join, channels, mod_state} when is_list(channels) ->
        init_ack(starter)
        enter_join(module, mod_state, channels, name, opts, :infinity)
      {:join, channels, mod_state, timeout} when is_list(channels) ->
        init_ack(starter)
        enter_join(module, mod_state, channels, name, opts, timeout)
      :ignore ->
        init_stop(starter, name, :ignore)
      {:stop, reason} ->
        init_stop(starter, name, reason)
      other ->
        init_stop(starter, name, {:bad_return_value, other})
    end
  end

  ##
  # Enters the `GenServer` loop.
  #
  # Args:
  #   * `module` - Module name.
  #   * `mod_state` - Initial state of the module.
  #   * `name` - Name of the server.
  #   * `opts` - Options.
  #   * `timeout` - Timeout or `:hibernate` flag.
  @doc false
  def enter_loop(module, mod_state, name, opts, :hibernate) do
    args = [module, mod_state, name, opts, :infinity]
    :proc_lib.hibernate(__MODULE__, :enter_loop, args)
  end

  def enter_loop(module, mod_state, name, opts, timeout)
      when name === self() do
    state = %YProcess{module: module, mod_state: mod_state}
    :gen_server.enter_loop(__MODULE__, opts, state, timeout)
  end

  def enter_loop(module, mod_state, name, opts, timeout) do
    state = %YProcess{module: module, mod_state: mod_state}
    :gen_server.enter_loop(__MODULE__, opts, state, name, timeout)
  end

  @doc false
  def init(_) do
    {:stop, __MODULE__}
  end

  @doc false
  def handle_call(request, from, state) do
    handle_sync(request, from, state)
  end

  @doc false
  def handle_cast(request, %YProcess{} = state) do
    handle_async(:handle_cast, request, state)
  end

  @doc false
  def handle_info(request, %YProcess{} = state) do
    handle_async(:handle_info, request, state)
  end

  @doc false
  def code_change(old_vsn,
                  %YProcess{module: module, mod_state: mod_state} = state,
                  extra) do
    try do
      apply(module, :code_change, [old_vsn, mod_state, extra])
    catch
      :throw, value ->
        exit({{:nocatch, value}, System.stacktrace()})
    else
      {:ok, mod_state} ->
        {:ok, %YProcess{state | mod_state: mod_state}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def terminate(reason, %YProcess{module: module, mod_state: mod_state}) do
    apply(module, :terminate, [reason, mod_state])
  end

  @doc false
  def format_status(:normal, [pdict, %YProcess{module: module,
                                               mod_state: mod_state}]) do
    try do
      apply(module, :format_status, [:normal, [pdict, mod_state]])
    catch
      _, _ ->
        [{:data, [{'State', mod_state}]}]
    else
      mod_status -> mod_status
    end
  end
  def format_status(:terminate, [pdict, %YProcess{module: module,
                                                 mod_state: mod_state}]) do
    try do
      apply(module, :format_status, [:terminate, [pdict, mod_state]])
    catch
      _, _ -> mod_state
    else
      mod_state -> mod_state
    end
  end

  #############################################################################
  # Start helper.

  ##
  # Starts the `GenServer`.
  #
  # Args:
  #   * `module` - Module name.
  #   * `args` - Module `init/1` arguments.
  #   * `options` - `GenServer` options.
  #   * `link` - Whether is `:link`ed to the parent process or not (`:nolink`).
  defp start(module, args, options, link) do
    case Keyword.pop(options, :name) do
      {nil, opts} ->
        :gen.start(__MODULE__, link, module, args, opts)
      {atom, opts} when is_atom(atom) ->
        :gen.start(__MODULE__, link, {:local, atom}, module, args, opts)
      {{:global, _} = name, opts} ->
        :gen.start(__MODULE__, link, name, module, args, opts)
      {{:via, _, _} = name, opts} ->
        :gen.start(__MODULE__, link, name, module, args, opts)
    end
  end

  #############################################################################
  # Initialization helpers.

  ##
  # Stops the `GenServer` on initialization.
  @spec init_stop(starter :: pid, name :: term, reason :: :ignore | term) ::
    no_return
  defp init_stop(starter, name, :ignore) do
    _ = unregister(name)
    :proc_lib.init_ack(starter, :ignore)
    exit(:normal)
  end
  defp init_stop(starter, name, reason) do
    _ = unregister(name)
    :proc_lib.init_ack(starter, {:error, reason})
    exit(reason)
  end

  ##
  # Unregisters `GenServer` name.
  defp unregister(name) when name == self(), do: :ok
  defp unregister({:local, name}), do: Process.unregister(name)
  defp unregister({:global, name}), do: Process.unregister(name)
  defp unregister({:via, mod, name}), do: apply(mod, :unregister_name, [name])

  ##
  # Sends the PID of the `GenServer` to the process starter on initialization.
  defp init_ack(starter) do
    :proc_lib.init_ack(starter, {:ok, self()})
  end

  ##
  # Enters the `GenServer` loop, but first creates the channels.
  defp enter_create(module, mod_state, channels, name, opts, timeout) do
    try do
      create(channels)
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_terminate(module, mod_state, name, reason, report)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_terminate(module, mod_state, name, reason, {:EXIT, reason})
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_terminate(module, mod_state, name, reason, {:EXIT, reason})
    else
      :ok ->
        enter_loop(module, mod_state, name, opts, timeout)
    end
  end

  ##
  # Creates the channels.
  defp create(channels) when is_list(channels) do
    _ = channels |> Enum.map(&create/1)
    :ok
  end
  defp create(channel) do
    id = {@channel_header, channel}
    created? = :ok == :pg2.create(id)
    if not created?, do: exit({:cannot_create_channel, channel}), else: id
  end

  ##
  # Deletes the channels.
  defp delete(channels) when is_list(channels) do
    _ = channels |> Enum.map(&delete/1)
    :ok
  end
  defp delete(channel) do
    id = {@channel_header, channel}
    :pg2.delete(id)
  end

  ##
  # Enters the `GenServer` loop, but first joins the channels.
  defp enter_join(module, mod_state, channels, name, opts, timeout) do
    try do
      join(channels)
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_terminate(module, mod_state, name, reason, report)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_terminate(module, mod_state, name, reason, {:EXIT, reason})
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_terminate(module, mod_state, name, reason, {:EXIT, reason})
    else
      :ok ->
        enter_loop(module, mod_state, name, opts, timeout)
    end
  end

  ##
  # Invokes `module.terminate/2` and stops the `GenServer`.
  @spec enter_terminate(module, mod_state, name, reason, report) ::
    no_return
      when mod_state: term, name: term, reason: term, report: term
  defp enter_terminate(module, mod_state, name, reason, report) do
    try do
      apply(module, :terminate, [reason, mod_state])
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_stop(module, mod_state, name, reason, report)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_stop(module, mod_state, name, reason, {:EXIT, reason})
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_stop(module, mod_state, name, reason, {:EXIT, reason})
    else
      _ ->
        enter_stop(module, mod_state, name, reason, report)
    end
  end

  @spec enter_stop(module, mod_state, name, reason, report) ::
    no_return
      when mod_state: term, name: term, reason: term, report: term
  defp enter_stop(_, _, _, :normal, {:EXIT, {{:stop, :normal}, _}}), do:
    exit(:normal)
  defp enter_stop(_, _, _, :shutdown, {:EXIT, {{:stop, :shutdown}, _}}), do:
    exit(:shutdown)
  defp enter_stop(_, _, _, {:shutdown, _} = shutdown,
                  {:EXIT, {{:stop, shutdown}, _}}), do:
    exit(shutdown)
  defp enter_stop(module, mod_state, name, reason, {_, report}) do
    state = %YProcess{module: module, mod_state: mod_state}
    mod_state = format_status(:terminate, [Process.get(), state])
    format = '**Generic server ~p terminating ~n' ++
      '** Last message in was ~p~n' ++ ## No last message
      '** When Server state == ~p~n' ++
      '** Reason for termination == ~n** ~p~n'
    args = [report_name(name), nil, mod_state, report_reason(report)]
    :error_logger.format(format, args)
    exit(reason)
  end

  defp report_name(name) when name == self(), do: name
  defp report_name({:local, name}), do: name
  defp report_name({:global, name}), do: name
  defp report_name({:via, _, name}), do: name

  defp report_reason({:undef, [{mod, fun, args, _} | _] = stack} = reason) do
    cond do
      :code.is_loaded(mod) === false ->
        {:"module could not be loaded", stack}
      not function_exported?(mod, fun, length(args)) ->
        {:"function not exported", stack}
      true ->
        reason
    end
  end
  defp report_reason(reason), do: reason

  #############################################################################
  # Basic functions helpers.

  ##
  # Joins the channels.
  defp join(channels) when is_list(channels) do
    _ = channels |> Enum.map(&join/1)
    :ok
  end
  defp join(channel) do
    id = create(channel)
    is_subscribed? = id |> :pg2.get_members |> Enum.member?(self())
    if not is_subscribed? do
      case :pg2.join(id, self) do
        :ok -> :ok
        {:error, _} -> exit({:cannot_join_channel, channel})
      end
    else
      :ok
    end
  end

  ##
  # Leaves the channels.
  defp leave(channels) when is_list(channels) do
    _ = channels |> Enum.map(&leave/1)
    :ok
  end
  defp leave(channel) do
    id = {@channel_header, channel}
    _ = :pg2.leave(id, self())
    :ok
  end

  ##
  # Emits messages without confirmation.
  defp emit_noack(channels, message) when is_list(channels) do
    channels |> Enum.map(&(emit_noack(&1, message)))
  end
  defp emit_noack(channel, message) do
    request = {@event_header, channel, message}
    {@channel_header, channel}
     |> :pg2.get_members
     |> Enum.map(&(YProcess.cast(&1, request)))
  end

  ##
  # Emits messages with confirmation.
  defp emit_ack(channels, message, timeout) when is_list(channels) do
    channels
     |> Enum.map(&(emit_ack(&1, message, timeout)))
  end
  defp emit_ack(channel, message, timeout) do
    pid = self()
    {@channel_header, channel}
     |> :pg2.get_members
     |> Enum.map(&(send_message(pid, &1, channel, message, timeout)))
  end

  ##
  # Sends a message to a PID.
  defp send_message(starter, pid, channel, message, timeout) do
    request = {@event_header, channel, message}
    try do
      YProcess.call(pid, request, timeout)
    catch
      _, _ -> send starter, {@no_deliver, channel, message, pid}
    else
      :ack -> send starter, {@deliver, channel, message, pid}
      _ -> send starter, {@no_deliver, channel, message, pid}
    end
  end

  ##
  # Naïve emit implementation.
  defp emit(channels, message) do
    emit_noack(channels, message)
  end
  defp emit(channels, message, timeout) do
    emit_ack(channels, message, timeout)
  end

  #############################################################################
  # GenServer helpers.

  ##
  # Handles synchronous events.
  #
  # Args:
  #   * `request` - Request.
  #   * `from` - Process that sent the event.
  #   * `state` - `YProcess` state.
  defp handle_sync({@event_header, channel, message}, from,
                   %YProcess{module: module, mod_state: mod_state} = state) do
    try do
      apply(module, :handle_event, [channel, message, mod_state])
    catch
      :throw, value ->
        reply(from, :noack)
        :erlang.raise(:error, {:nocatch, value}, System.stacktrace())
    else
      {:noreply, mod_state} ->
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:noreply, mod_state, timeout} ->
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:create, channels, mod_state} when is_list(channels) ->
        _ = create(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:create, channels, mod_state, timeout} ->
        _ = create(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:delete, channels, mod_state} when is_list(channels) ->
        _ = delete(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:delete, channels, mod_state, timeout} ->
        _ = delete(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:join, channels, mod_state} when is_list(channels) ->
        _ = join(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:join, channels, mod_state, timeout} when is_list(channels) ->
        _ = join(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:leave, channels, mod_state} when is_list(channels) ->
        _ = leave(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:leave, channels, mod_state, timeout} ->
        _ = leave(channels)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit, channels, message, mod_state} ->
        _ = emit(channels, message)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:emit, channels, message, mod_state, timeout} ->
        _ = emit(channels, message)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit_ack, channels, message, ack_timeout, mod_state}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}}
      {:emit_ack, channels, message, ack_timeout, mod_state, timeout}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:reply, :ack, %YProcess{state | mod_state: mod_state}, timeout}
      {:stop, :normal, mod_state} ->
        {:stop, :ack, :normal, %YProcess{state | mod_state: mod_state}}
      {:stop, :shutdown, mod_state} ->
        {:stop, :ack, :shutdown, %YProcess{state | mod_state: mod_state}}
      {:stop, {:shutdown, _} = shutdown, mod_state} ->
        {:stop, :ack, shutdown, %YProcess{state | mod_state: mod_state}}
      {:stop, reason, mod_state} ->
        {:stop, :noack, reason, %YProcess{state | mod_state: mod_state}}
      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end
  defp handle_sync(request, from,
                   %YProcess{module: module, mod_state: mod_state} = state) do
    try do
      apply(module, :handle_call, [request, from, mod_state])
    catch
      :throw, value ->
        :erlang.raise(:error, {:nocatch, value}, System.stacktrace())
    else
      {:noreply, mod_state} ->
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:noreply, mod_state, timeout} ->
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:reply, reply, mod_state} ->
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:reply, reply, mod_state, timeout} ->
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:create, channels, reply, mod_state} when is_list(channels) ->
        _ = create(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:create, channels, reply, mod_state, timeout} ->
        _ = create(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:delete, channels, reply, mod_state} when is_list(channels) ->
        _ = delete(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:delete, channels, reply, mod_state, timeout} ->
        _ = delete(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:join, channels, reply, mod_state} when is_list(channels) ->
        _ = join(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:join, channels, reply, mod_state, timeout} when is_list(channels) ->
        _ = join(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:leave, channels, reply, mod_state} when is_list(channels) ->
        _ = leave(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:leave, channels, reply, mod_state, timeout} ->
        _ = leave(channels)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit, channels, message, reply, mod_state} ->
        _ = emit(channels, message)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:emit, channels, message, reply, mod_state, timeout} ->
        _ = emit(channels, message)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit_ack, channels, message, ack_timeout, reply, mod_state}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:reply, reply, %YProcess{state | mod_state: mod_state}}
      {:emit_ack, channels, message, ack_timeout, reply, mod_state, timeout}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:reply, reply, %YProcess{state | mod_state: mod_state}, timeout}
      {:stop, reason, reply, mod_state} ->
        {:stop, reply, reason, %YProcess{state | mod_state: mod_state}}
      other ->
        {:stop, {:bad_return_value, other}, state}
    end

  end

  ##
  # Handles asynchronous requests.
  #
  # Args:
  #   * `callback` - Type. Either `:handle_cast` or `:handle_info`.
  #   * `request` - Request.
  #   * `state` - `YProcess` state.
  defp handle_async(callback, request, %YProcess{} = state) do
    try do
      async_event(callback, request, state)
    catch
      :throw, value ->
        :erlang.raise(:error, {:nocatch, value}, System.stacktrace())
    else
      {:noreply, mod_state} = noreply ->
        _ = put_elem(noreply, 1, %YProcess{state | mod_state: mod_state})
      {:noreply, mod_state, _} = noreply ->
        _ = put_elem(noreply, 1, %YProcess{state | mod_state: mod_state})
      {:create, channels, mod_state} when is_list(channels) ->
        _ = create(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:create, channels, mod_state, timeout} ->
        _ = create(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:delete, channels, mod_state} when is_list(channels) ->
        _ = delete(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:delete, channels, mod_state, timeout} ->
        _ = delete(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:join, channels, mod_state} ->
        _ = join(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:join, channels, mod_state, timeout} ->
        _ = join(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:leave, channels, mod_state} ->
        _ = leave(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:leave, channels, mod_state, timeout} ->
        _ = leave(channels)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit, channels, message, mod_state} ->
        _ = emit(channels, message)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:emit, channels, message, mod_state, timeout} ->
        _ = emit(channels, message)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:emit_ack, channels, message, ack_timeout, mod_state}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:noreply, %YProcess{state | mod_state: mod_state}}
      {:emit_ack, channels, message, ack_timeout, mod_state, timeout}
          when is_integer(ack_timeout) ->
        _ = emit(channels, message, ack_timeout)
        {:noreply, %YProcess{state | mod_state: mod_state}, timeout}
      {:stop, _, mod_state} = stop ->
        _ = put_elem(stop, 2, %YProcess{state | mod_state: mod_state})
      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end

  ##
  # Handles asynchronous events.
  #
  # Args:
  #   * `callback` - Callback to call.
  #   * `message` - Message.
  #   * `state` - `YProcess` state.
  defp async_event(_,
                   {@event_header, channel, message},
                   %YProcess{module: module, mod_state: mod_state}) do
    apply(module, :handle_event, [channel, message, mod_state])
  end
  defp async_event(callback, request,
                   %YProcess{module: module, mod_state: mod_state}) do
    apply(module, callback, [request, mod_state])
  end
end
