defmodule YProcess.Backend.PhoenixPubSubTest do
  use ExUnit.Case, async: true

  setup_all do
    Application.put_env(:y_process, :opts, [app_name: MyApp.Endpoint])
    Application.put_env(:y_process, MyApp.Endpoint,
      [pubsub: [adapter: Phoenix.PubSub.PG2,
                pool_size: 1,
                name: MyApp.PubSub]])
    {:ok, _} = Phoenix.PubSub.PG2.start_link(MyApp.Endpoint, [])
    :ok
  end

  test "join/2, leave/2 and emit/2" do
    Application.get_env(:y_process, :opts)
    Application.get_env(:y_process, TestApp.Endpoint)
    channel = make_ref()
    pid = self()
    assert :ok = YProcess.Backend.PhoenixPubSub.join(channel, pid)
    assert :ok = YProcess.Backend.PhoenixPubSub.join(channel, pid)
    YProcess.Backend.PhoenixPubSub.emit(channel, "message")
    assert_receive "message"
    assert {:messages, []} = Process.info(pid, :messages)
    assert :ok = YProcess.Backend.PhoenixPubSub.leave(channel, pid)
  end
end
