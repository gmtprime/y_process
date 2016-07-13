# YProcess

[![Build Status](https://travis-ci.org/gmtprime/y_process.svg?branch=master)](https://travis-ci.org/gmtprime/y_process) [![Hex pm](http://img.shields.io/hexpm/v/y_process.svg?style=flat)](https://hex.pm/packages/y_process) [![hex.pm downloads](https://img.shields.io/hexpm/dt/y_process.svg?style=flat)](https://hex.pm/packages/y_process) [![Deps Status](https://beta.hexfaktor.org/badge/all/github/gmtprime/y_process.svg)](https://beta.hexfaktor.org/github/gmtprime/y_process) [![Inline docs](http://inch-ci.org/github/gmtprime/y_process.svg?branch=master)](http://inch-ci.org/github/gmtprime/y_process)

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

The backend behaviour defines the way the processes create, delete, join, leave
channels and emit messages. By default, the processes use the
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

To use a backend, just modify the configuration of the application (explained in
the next sections) or pass the backend in the module definition i.e:

    defmodule Test do
      use YProcess, backend: YProcess.Backend.PhoenixPubSub
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

To configure the backend globally for all the `YProcess`es just set the following:

* For `YProcess.Backend.PG2`

        config :y_process,
          backend: YProces.Backend.PG2

* For `YProcess.Backend.PhoenixPubSub`

        config :y_process,
          backend: YProcess.Backend.PhoenixPubSub
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

## Author

Alexander de Sousa

## Credits

`YProcess` owns its existence to the extensive study and "code borrowing" from
`Connection`.

## License

`YProcess` is released under the MIT License. See the LICENSE file for further
details.
