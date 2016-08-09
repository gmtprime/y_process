defmodule YProcess do
  @moduledoc """
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

  ## Backends

  The backend behaviour defines the way the processes create, delete, join,
  leave channels and emit messages. By default, the processes use the
  `YProcess.Backend.PG2` backend that uses `:pg2`, but it is possible to use the
  `YProcess.Backend.PhoenixPubSub` that uses phoenix pubsub and also use any of
  its adapters.

  The backend behaviour needs to implement the following callbacks:

      # Callback to create a `channel`.
      @callback create(channel) :: :ok | {:error, reason}
        when channel: YProcess.channel, reason: term

      # Callback to delete a `channel`.
      @callback delete(channel) :: :ok | {:error, reason}
        when channel: YProcess.channel, reason: term

      # Callback used to make a process with `pid` a `channel`.
      @callback join(channel, pid) :: :ok | {:error, reason}
        when channel: YProcess.channel, reason: term

      # Callback used to make a process with `pid` leave a `channel`.
      @callback leave(channel, pid) :: :ok | {:error, reason}
        when channel: YProcess.channel, reason: term

      # Callback used to send a `message` to a `channel`.
      @callback emit(channel, message) :: :ok | {:error, reason}
        when channel: YProcess.channel, message: term, reason: term

  To use a backend, just modify the configuration of the application (explained
  in the next sections) or pass the backend in the module definition i.e:

      defmodule Test do
        use YProcess, backend: Backend.PhoenixPubSub
        (...)
      end

  For the backends provided, there are two aliases for the modules:

  * `:pg2` for `YProcess.Backend.PG2`
  * `:phoenix_pub_sub` for `YProcess.Backend.PhoenixPubSub`

  The shorter version of the module `Test` defined above would be:

      defmodule Test do
        use YProcess, backend: :phoenix_pub_sub
        (...)
      end

  ### Backend Configuration

  To configure the backend globally for all the `YProcess`es just set the
  following:

  * For `YProcess.Backend.PG2`

          config :y_process,
            backend: YProces.Backend.PG2

  * For `YProcess.Backend.PhoenixPubSub`

          config :y_process,
            backend: Backend.PhoenixPubSub
            opts: [app_name: MyApp.Endpoint]

          # Phoenix PubSub configuration. Look at Phoenix PubSub documentation
          # for more information.
          config :my_app, MyApp.Endpoint,
            pubsub: [adapter: Phoenix.PubSub.PG2,
                     pool_size: 1,
                     name: MyApp.PubSub]

  where `:my_app` is the name of the application.

  ## Installation

  Add `YProcess` as a dependency in your `mix.exs` file.

      def deps do
          [{:y_process, "~> 0.0.2"}]
      end

  After you're done, run this in your shell to fetch the new dependency:

      $ mix deps.get

  """
  use Behaviour
  @behaviour :gen_server
  alias __MODULE__, as: YProcess
  alias YProcess.Backend

  ##########
  # Headers.

  @cast_header :"Y_CAST_EVENT"
  @call_header :"Y_CALL_EVENT"
  @ack_header :"Y_ACK_EVENT"

  ########
  # Types.

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

  @typedoc "Asynchronous callback response."
  @type async_response ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:create, channels, new_state} |
    {:create, channels, new_state, timeout | :hibernate} |
    {:emit, channels, new_message, new_state} |
    {:emit, channels, new_message, new_state, timeout | :hibernate} |
    {:emit_ack, channels, new_message, new_state} |
    {:emit_ack, channels, new_message, new_state, timeout | :hibernate} |
    {:join, channels, new_state} |
    {:join, channels, new_state, timeout | :hibernate} |
    {:leave, channels, new_state} |
    {:leave, channels, new_state, timeout | :hibernate} |
    {:delete, channels, new_state} |
    {:delete, channels, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state}

  @typedoc "Synchronous callback response."
  @type sync_response ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:rcreate, channels, reply, new_state} |
    {:rcreate, channels, reply, new_state, timeout | :hibernate} |
    {:remit, channels, new_message, reply, new_state} |
    {:remit, channels, new_message, reply, new_state, timeout | :hibernate} |
    {:remit_ack, channels, new_message, reply, new_state} |
    {:remit_ack, channels, new_message, reply, new_state,
     timeout | :hibernate} |
    {:rjoin, channels, reply, new_state} |
    {:rjoin, channels, reply, new_state, timeout | :hibernate} |
    {:rleave, channels, reply, new_state} |
    {:rleave, channels, reply, new_state, timeout | :hibernate} |
    {:rdelete, channels, reply, new_state} |
    {:rdelete, channels, reply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, reply, new_state} |
    async_response


  ############
  # Callbacks.

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
    {:stop, reason :: any}
      when state: any, channels: list

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

  Returning `{:rcreate, channels, reply, new_state}` will create the `channels`
  and `reply` back to `call/3` caller.

  Returning `{:rcreate, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:rcreate, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:remit, channels, message, reply, new_state}` will emit a
  `message` in several `channels` while replying back to the `call/3` caller.
  The `YProcess` does not receive confirmations for the messages sent.

  Returning
  `{:remit, channels, message, reply, new_state, timeout | :hibernate}`
  is similar to `{:remit, channels, message, new_state}` except a timeout
  or hibernation occurs as with the `:reply` tuple.

  Returning `{:remit_ack, channels, message, reply, new_state}`
  will emit a `message` in several `channels` while sending a `reply` back to
  the `call/3` caller. The `YProcess` receives confirmations from every
  subscriber in `handle_info/2`. The confirmation message is
  `{:DELIVER, pid, channel, message}` where `pid` is the PID of the subscriber.

  Returning
  `{:remit_ack, channels, message, reply, new_state, timeout | :hibernate}`
  is similar to `{:remit_ack, channels, message, reply, new_state}`
  except a timeout or hibernation occurs as with the `:reply` tuple.

  Returning `{:rjoin, channels, reply, new_state}` will join the `YProcess`
  to the `channels` and send a `reply` back to the `call/3` caller.

  Returning `{:rjoin, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:rjoin, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:rleave, channels, reply, new_state}` the `YProcess` will
  leave the `channels` and send a `reply` back to the `call/3` caller.

  Returning `{:rleave, channels, reply, new_state, timeout | :hibernate}` is
  similar to `{:rleave, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:rdelete, channels, reply, new_state}` will delete the `channels`
  and `reply` back to `call/3` caller.

  Returning `{:rdelete, channels, reply, new_state, timeout | :hibernate}`
  is similar to `{:rdelete, channels, reply, new_state}` except a timeout or
  hibernation occurs as with the `:reply` tuple.

  Returning `{:stop, reason, reply, new_state}` stops the loop and
  `terminate/2` is called with reason `reason` and `new_state`. Then the
  `reply` is sent as response to the call and the process exist with `reason`.

  Returning `{:stop, reason, new_state}` is similar to
  `{:stop, reason, reply, new_state}` except a reply is not sent.

  It also returns the same tuples from `handle_cast/2`.
  """
  @callback handle_call(request :: term, from :: {pid, term}, state :: term) ::
    sync_response

  @doc """
  Invoked to handle asynchronous `cast/2` messages.

  `request` is the request message sent by a `cast/2` and `state` is the current
  state of the `YProcess`.

  Returning `{:noreply, new_state}` updates the current state to the
  `new_state`.

  Returning `{:noreply, new_state, timeout}` is similar to
  `{:noreply, new_state}` except `handle_info(:timeout, new_state)` will
  be called after `timeout` milliseconds if no messages are received.

  Returning `{:noreply, new_state, :hibernate}` is similar to
  `{:noreply, new_state}` except the process is hibernated and will
  continue the loop once a messages is in its message queue. If a message is
  already in the message queue this will immediately. Hibernating a `YProcess`
  causes garbage collection and leaves a continuous heap that minimises the
  memory used by the process.

  Hibernating should not be used aggressively as too much time could be spent
  garbage collecting. Normally, it should be only be used when a message is not
  expected soon and minimising the memory of the process is shown to be
  beneficial.

  Returning `{:create, channels, new_state}` similar to
  `{:rcreate, channels, reply, new_state}` in `handle_call/3`, but with no
  reply to the caller.

  Returning `{:create, channels, new_state, timeout | :hibernate}` is similar to
  `{:rcreate, channels, reply, new_state, timeout | :hibernate}` in
  `handle_call/3`, but with no reply to the caller.

  Returning `{:delete, channels, new_state}` similar to
  `{:rdelete, channels, reply, new_state}` in `handle_call/3`, but with no
  reply to the caller.

  Returning `{:delete, channels, new_state, timeout | :hibernate}` is similar
  to `{:rdelete, channels, reply, new_state, timeout | :hibernate}` in
  `handle_call/3`, but with no reply to the caller.

  Returning `{:join, channels, new_state}` similar to
  `{:rjoin, channels, reply, new_state}` in `handle_call/3`, but with no
  reply to the caller.

  Returning `{:join, channels, new_state, timeout | :hibernate}` is similar to
  `{:rjoin, channels, reply, new_state, timeout | :hibernate}` in
  `handle_call/3`, but with no reply to the caller.

  Returning `{:leave, channels, new_state}` similar to
  `{:rleave, channels, reply, new_state}` in `handle_call/3`, but with no
  reply to the caller.

  Returning `{:leave, channels, new_state, timeout | :hibernate}` is similar to
  `{:rleave, channels, reply, new_state, timeout | :hibernate}` in
  `handle_call/3`, but with no reply to the caller.

  Returning `{:emit, channels, message, new_state}` similar to
  `{:remit, channels, message, reply, new_state}` in `handle_call/3`, but
  with no reply to the caller.

  Returning `{:emit, channels, message, new_state, timeout | :hibernate}` is
  similar to
  `{:remit, channels, message, reply, new_state, timeout | :hibernate}`
  in `handle_call/3`, but with no reply to the caller.

  Returning `{:emit_ack, channels, message, new_state}` similar to
  `{:remit_ack, channels, message, reply, new_state}` in `handle_call/3`,
  but with no reply to the caller.

  Returning `{:emit_ack, channels, message, new_state, timeout | :hibernate}` is
  similar to
  `{:remit_ack, channels, message, reply, new_state, timeout | :hibernate}`
  in `handle_call/3`, but with no reply to the caller.

  Returning `{:stop, reason, new_state}` stops the `YProcess` with `reason`.
  """
  @callback handle_cast(request :: term, state :: term) :: async_response

  @doc """
  Invoked to handle all other messages.

  Receives the `message` and the current `YProcess` `state`. When a timeout
  occurs the message is `:timeout`.

  Returns the same output as `handle_cast/2`.
  """
  @callback handle_info(message :: term | :timeout, state :: term) ::
    async_response

  @doc """
  Invoked to handle messages coming from a registered channel.

  `channel` is the channel from which the `message` is been received. `state`
  is the current state of the `YProcess`.

  Returns the same output as `handle_cast/2`
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

  @doc false
  def get_backend(backend) do
    case backend do
      nil ->
        value = Application.get_env(:y_process, :backend, Backend.PG2)
        get_backend(value)
      :pg2 -> Backend.PG2
      :phoenix_pubsub -> Backend.PhoenixPubSub
      other -> other
    end
  end

  defmacro __using__(opts) do
    backend = opts |> Keyword.get(:backend) |> get_backend
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      @doc false
      def get_backend do
        unquote(backend)
      end

      @doc false
      def init(args) do
        {:ok, args}
      end

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
      def handle_info(_message, state) do
        {:noreply, state}
      end

      @doc false
      def handle_event(channel, message, state) do
        reason = {:bad_event, {channel, message}}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, state}
        end
      end

      @doc false
      def terminate(_reason, _state) do
        :ok
      end

      @doc false
      def code_change(_olv_vsn, state, _extra) do
        {:ok, state}
      end

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

  defstruct [:module, :mod_state, :backend]

  #############################################################################
  # Callback definition.

  defp gen_state(module, mod_state, backend) do
    %YProcess{module: module, mod_state: mod_state, backend: backend}
  end

  ##
  # Initializes the `GenServer`.
  @doc false
  def init_it(starter, _, name, module, args, opts) do
    # There is no init/1 defined, but this function simulates it.
    Process.put(:"$initial_call", {module, :init, 1})
    backend = module.get_backend()
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
        state = gen_state(module, mod_state, backend)
        enter_loop(name, opts, :infinity, state)
      {:ok, mod_state, timeout} ->
        init_ack(starter)
        state = gen_state(module, mod_state, backend)
        enter_loop(name, opts, timeout, state)
      {:create, channels, mod_state} when is_list(channels) ->
        init_ack(starter)
        state = gen_state(module, mod_state, backend)
        enter_create(channels, name, opts, :infinity, state)
      {:create, channels, mod_state, timeout} when is_list(channels) ->
        init_ack(starter)
        state = gen_state(module, mod_state, backend)
        enter_create(channels, name, opts, timeout, state)
      {:join, channels, mod_state} when is_list(channels) ->
        init_ack(starter)
        state = gen_state(module, mod_state, backend)
        enter_join(channels, name, opts, :infinity, state)
      {:join, channels, mod_state, timeout} when is_list(channels) ->
        init_ack(starter)
        state = gen_state(module, mod_state, backend)
        enter_join(channels, name, opts, timeout, state)
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
  #   * `name` - Name of the server.
  #   * `opts` - Options.
  #   * `timeout` - Timeout or `:hibernate` flag.
  #   * `state` - YProcess state.
  @doc false
  def enter_loop(name, opts, :hibernate, state) do
    args = [name, opts, :infinity, state]
    :proc_lib.hibernate(__MODULE__, :enter_loop, args)
  end

  def enter_loop(name, opts, timeout, state)
      when name === self() do
    :gen_server.enter_loop(__MODULE__, opts, state, timeout)
  end

  def enter_loop(name, opts, timeout, state) do
    :gen_server.enter_loop(__MODULE__, opts, state, name, timeout)
  end

  ################################
  # GenServer callback definition.

  @doc false
  def init(_) do
    {:stop, __MODULE__}
  end

  @doc false
  def handle_call(request, from, state) do
    handle_message(:handle_call, request, from, state)
  end

  @doc false
  def handle_cast(request, %YProcess{} = state) do
    handle_message(:handle_cast, request, nil, state)
  end

  @doc false
  def handle_info({@cast_header, _, _} = request, %YProcess{} = state) do
    handle_message(:handle_event, request, nil, state)
  end
  def handle_info({@call_header, _, _, _} = request, %YProcess{} = state) do
    handle_message(:handle_event, request, nil, state)
  end
  def handle_info({@ack_header, _, pid, _, _}, %YProcess{} = state)
      when pid != self() do
    {:noreply, state}
  end
  def handle_info({@ack_header, subscriber, _, channel, message}, %YProcess{} = state) do
    request = {:DELIVERED, subscriber, channel, message}
    handle_message(:handle_info, request, nil, state)
  end
  def handle_info(request, %YProcess{} = state) do
    handle_message(:handle_info, request, nil, state)
  end

  @doc false
  def code_change(old_vsn, %YProcess{} = state, extra) do
    try do
      apply(state.module, :code_change, [old_vsn, state.mod_state, extra])
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
  def format_status(:normal, [pdict, %YProcess{module: module, mod_state: mod_state}]) do
    try do
      apply(module, :format_status, [:normal, [pdict, mod_state]])
    catch
      _, _ ->
        [{:data, [{'State', mod_state}]}]
    else
      mod_status -> mod_status
    end
  end
  def format_status(:terminate, [pdict, %YProcess{module: module, mod_state: mod_state}]) do
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
  defp enter_create(channels, name, opts, timeout, %YProcess{} = state) do
    try do
      Backend.create(state.backend, channels)
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_terminate(name, reason, report, state)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_terminate(name, reason, {:EXIT, reason}, state)
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_terminate(name, reason, {:EXIT, reason}, state)
    else
      :ok ->
        enter_loop(name, opts, timeout, state)
    end
  end

  ##
  # Enters the `GenServer` loop, but first joins the channels.
  defp enter_join(channels, name, opts, timeout, %YProcess{} = state) do
    try do
      Backend.join(state.backend, channels)
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_terminate(name, reason, report, state)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_terminate(name, reason, {:EXIT, reason}, state)
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_terminate(name, reason, {:EXIT, reason}, state)
    else
      :ok ->
        enter_loop(name, opts, timeout, state)
    end
  end

  ##
  # Invokes `module.terminate/2` and stops the `GenServer`.
  @spec enter_terminate(name, reason, report, state) ::
    no_return
      when name: term, reason: term, report: term, state: term
  defp enter_terminate(name, reason, report, %YProcess{} = state) do
    try do
      apply(state.module, :terminate, [reason, state.mod_state])
    catch
      :exit, reason ->
        report = {:EXIT, {reason, System.stacktrace()}}
        enter_stop(name, reason, report, state)
      :error, reason ->
        reason = {reason, System.stacktrace()}
        enter_stop(name, reason, {:EXIT, reason}, state)
      :throw, value ->
        reason = {{:nocatch, value}, System.stacktrace()}
        enter_stop(name, reason, {:EXIT, reason}, state)
    else
      _ ->
        enter_stop(name, reason, report, state)
    end
  end

  @spec enter_stop(name, reason, report, state) ::
    no_return
      when name: term, reason: term, report: term, state: term
  defp enter_stop(_, :normal, {:EXIT, {{:stop, :normal}, _}}, _), do:
    exit(:normal)
  defp enter_stop(_, :shutdown, {:EXIT, {{:stop, :shutdown}, _}}, _), do:
    exit(:shutdown)
  defp enter_stop(_, {:shutdown, _} = shutdown,
                  {:EXIT, {{:stop, shutdown}, _}}, _), do:
    exit(shutdown)
  defp enter_stop(name, reason, {_, report}, state) do
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
  # GenServer helpers.

  defp gen_cast_message(channel, message) do
    {@cast_header, channel, message}
  end

  defp gen_call_message(from) do
    fn channel, message ->
      {@call_header, channel, message, from}
    end
  end

  ##
  # Acks a message.
  #
  # Args:
  #   * `receiver_pid` - Receiver PID.
  #   * `from` - Connection reference.
  defp send_ack_message(receiver_pid, sender_pid, channel, message) do
    ack = {@ack_header, receiver_pid, sender_pid, channel, message}
    send sender_pid, ack
  end

  ##
  # Handles requests.
  #
  # Args:
  #   * `callback` - Callback name.
  #   * `request` - Request message
  #   * `from` - Reference to the process which sent the request.
  #   * `state` - YProcess state.
  #
  # Returns:
  #   `GenServer` response.
  defp handle_message(
    :handle_event,
    {@call_header, channel, message, from},
    nil,
    %YProcess{module: module, mod_state: mod_state} = state
  ) do
    handle_async(fn ->
      send_ack_message(self(), from, channel, message)
      apply(module, :handle_event, [channel, message, mod_state])
    end, state)
  end
  defp handle_message(
    :handle_event,
    {@cast_header, channel, message},
    nil,
    %YProcess{module: module, mod_state: mod_state} = state
  ) do
    handle_async(fn ->
      apply(module, :handle_event, [channel, message, mod_state])
    end, state)
  end
  defp handle_message(
    callback,
    request,
    nil,
    %YProcess{module: module, mod_state: mod_state} = state
  ) do
    handle_async(fn ->
      apply(module, callback, [request, mod_state])
    end, state)
  end
  defp handle_message(
    callback,
    request,
    from,
    %YProcess{module: module, mod_state: mod_state} = state
  ) do
    handle_sync(fn ->
      apply(module, callback, [request, from, mod_state])
    end, from, state)
  end

  ##
  # Handles asynchronous requests.
  #
  # Args:
  #   * `function` - Function to handle the message as `YProcess`.
  #   * `state` - `YProcess` state.
  #
  # Returns:
  #   `GenServer` response.
  defp handle_async(function, %YProcess{} = state) do
    try do
      function.()
    catch
      :throw, value ->
        :erlang.raise(:error, {:nocatch, value}, System.stacktrace())
    else
      response ->
        cast_response(response, state)
    end
  end

  ##
  # Handles synchronous requests.
  #
  # Args:
  #   * `function` - Function to handle the message as `YProcess`.
  #   * `from` - From tuple.
  #   * `state` - `YProcess` state.
  #
  # Returns:
  #   `GenServer` response.
  defp handle_sync(function, from, %YProcess{} = state) do
    try do
      function.()
    catch
      :throw, value ->
        :erlang.raise(:error, {:nocatch, value}, System.stacktrace())
    else
      response ->
        call_response(response, from, state)
    end
  end

  ##
  # Handles asynchronous responses.
  #
  # Args:
  #   * `response` - Response from `YProcess` callbacks.
  #   * `state` - `YProcess` state.
  #
  # Returns:
  #   `GenServer` response.
  defp cast_response({:noreply, mod_state}, %YProcess{} = state) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response({:noreply, mod_state, timeout}, %YProcess{} = state) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:create, channels, mod_state},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.create(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:create, channels, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.create(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:delete, channels, mod_state},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.delete(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:delete, channels, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.delete(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:join, channels, mod_state},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.join(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:join, channels, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.join(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:leave, channels, mod_state},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.leave(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:leave, channels, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.leave(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:emit, channels, message, mod_state},
    %YProcess{backend: backend} = state
  ) do
    spawn_link fn ->
      Backend.emit(backend, channels, message, &gen_cast_message/2)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:emit, channels, message, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    spawn_link fn ->
      Backend.emit(backend, channels, message, &gen_cast_message/2)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:emit_ack, channels, message, mod_state},
    %YProcess{backend: backend} = state
  ) do
    sender = self()
    spawn_link fn ->
      Backend.emit(backend, channels, message, gen_call_message(sender))
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp cast_response(
    {:emit_ack, channels, message, mod_state, timeout},
    %YProcess{backend: backend} = state
  ) do
    sender = self()
    spawn_link fn ->
      Backend.emit(backend, channels, message, gen_call_message(sender))
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp cast_response(
    {:stop, reason, mod_state},
    %YProcess{} = state
  ) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:stop, reason, new_state}
  end
  defp cast_response(other, %YProcess{} = state) do
    {:stop, {:bad_return_value, other}, state}
  end

  ##
  # Handles synchronous responses.
  #
  # Args:
  #   * `response` - Response from `YProcess` callbacks.
  #   * `state` - `YProcess` state.
  #
  # Returns:
  #   `GenServer` response.
  defp call_response({:reply, reply, mod_state}, _from, %YProcess{} = state) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state}
  end
  defp call_response(
    {:reply, reply, mod_state, timeout},
    _from,
    %YProcess{} = state
  ) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state, timeout}
  end
  defp call_response(
    {:rcreate, channels, reply, mod_state},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.create(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state}
  end
  defp call_response(
    {:rcreate, channels, reply, mod_state, timeout},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.create(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state, timeout}
  end
  defp call_response(
    {:rdelete, channels, reply, mod_state},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.delete(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state}
  end
  defp call_response(
    {:rdelete, channels, reply, mod_state, timeout},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.delete(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state, timeout}
  end
  defp call_response(
    {:rjoin, channels, reply, mod_state},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.join(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state}
  end
  defp call_response(
    {:rjoin, channels, reply, mod_state, timeout},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.join(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state, timeout}
  end
  defp call_response(
    {:rleave, channels, reply, mod_state},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.leave(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state}
  end
  defp call_response(
    {:rleave, channels, reply, mod_state, timeout},
    _from,
    %YProcess{backend: backend} = state
  ) do
    _ = Backend.leave(backend, channels)
    new_state = %YProcess{state | mod_state: mod_state}
    {:reply, reply, new_state, timeout}
  end
  defp call_response(
    {:remit, channels, message, reply, mod_state},
    from,
    %YProcess{backend: backend} = state
  ) do
    spawn_link fn ->
      Backend.emit(backend, channels, message, &gen_cast_message/2)
      YProcess.reply(from, reply)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp call_response(
    {:remit, channels, message, reply, mod_state, timeout},
    from,
    %YProcess{backend: backend} = state
  ) do
    spawn_link fn ->
      Backend.emit(backend, channels, message, &gen_cast_message/2)
      YProcess.reply(from, reply)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp call_response(
    {:remit_ack, channels, message, reply, mod_state},
    from,
    %YProcess{backend: backend} = state
  ) do
    sender = self()
    spawn_link fn ->
      Backend.emit(backend, channels, message, gen_call_message(sender))
      YProcess.reply(from, reply)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state}
  end
  defp call_response(
    {:remit_ack, channels, message, reply, mod_state, timeout},
    from,
    %YProcess{backend: backend} = state
  ) do
    sender = self()
    spawn_link fn ->
      Backend.emit(backend, channels, message, gen_call_message(sender))
      YProcess.reply(from, reply)
    end
    new_state = %YProcess{state | mod_state: mod_state}
    {:noreply, new_state, timeout}
  end
  defp call_response(
    {:stop, reason, reply, mod_state},
    _from,
    %YProcess{} = state
  ) do
    new_state = %YProcess{state | mod_state: mod_state}
    {:stop, reason, reply, new_state}
  end
  defp call_response(other, _from, state) do
    cast_response(other, state)
  end
end
