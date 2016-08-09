defmodule YProcess.Backend.PhoenixPubSubTest do
  use ExUnit.Case, async: true

  setup_all do
    Application.put_env(:y_process, :name, MyApp.PubSub)
    Application.put_env(:y_process, :adapter, Phoenix.PubSub.PG2)
    Application.put_env(:y_process, :options, [pool_size: 1])
    {:ok, _} = YProcess.PhoenixPubSub.start_link()
    :ok
  end

  test "join/2, leave/2 and emit/2" do
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
