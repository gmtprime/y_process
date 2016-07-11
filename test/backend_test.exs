defmodule YProcess.BackendTest do
  use ExUnit.Case, async: true

  test "create/1 callback" do
    channel = "channel"
    {:ok, server} = EvalBackend.start_link()
    :ok = EvalBackend.create({server, channel})
    assert %{"channel" => []} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "delete/1 callback" do
    channel = "channel"
    {:ok, server} = EvalBackend.start_link()
    :ok = EvalBackend.create({server, channel})
    assert %{"channel" => []} = EvalBackend.state(server)
    :ok = EvalBackend.delete({server, channel})
    assert %{} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "join/2 callback" do
    channel = "channel"
    client = self() 
    {:ok, server} = EvalBackend.start_link()
    :ok = EvalBackend.create({server, channel})
    assert %{"channel" => []} = EvalBackend.state(server)
    :ok = EvalBackend.join({server, channel}, client)
    assert %{"channel" => [^client]} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "leave/2 callback" do
    channel = "channel"
    client = self() 
    {:ok, server} = EvalBackend.start_link()
    :ok = EvalBackend.create({server, channel})
    assert %{"channel" => []} = EvalBackend.state(server)
    :ok = EvalBackend.join({server, channel}, client)
    assert %{"channel" => [^client]} = EvalBackend.state(server)
    :ok = EvalBackend.leave({server, channel}, client)
    assert %{"channel" => []} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "emit/2 callback" do
    channel = "channel"
    client = self() 
    {:ok, server} = EvalBackend.start_link()
    :ok = EvalBackend.create({server, channel})
    assert %{"channel" => []} = EvalBackend.state(server)
    :ok = EvalBackend.join({server, channel}, client)
    assert %{"channel" => [^client]} = EvalBackend.state(server)
    :ok = EvalBackend.emit({server, channel}, "message")
    assert_receive "message"
    EvalBackend.stop(server)
  end

  test "create/2 function" do
    {:ok, server} = EvalBackend.start_link()
    channels = ["ch0", "ch1"] |> Enum.map(&({server, &1}))
    YProcess.Backend.create(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "delete/2 function" do
    {:ok, server} = EvalBackend.start_link()
    channels = ["ch0", "ch1"] |> Enum.map(&({server, &1}))
    YProcess.Backend.create(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    YProcess.Backend.delete(EvalBackend, channels)
    assert %{} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "join/2 function" do
    client = self()
    {:ok, server} = EvalBackend.start_link()
    channels = ["ch0", "ch1"] |> Enum.map(&({server, &1}))
    YProcess.Backend.create(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    YProcess.Backend.join(EvalBackend, channels)
    assert %{"ch0" => [^client], "ch1" => [^client]} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "leave/2 function" do
    client = self()
    {:ok, server} = EvalBackend.start_link()
    channels = ["ch0", "ch1"] |> Enum.map(&({server, &1}))
    YProcess.Backend.create(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    YProcess.Backend.join(EvalBackend, channels)
    assert %{"ch0" => [^client], "ch1" => [^client]} = EvalBackend.state(server)
    YProcess.Backend.leave(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    EvalBackend.stop(server)
  end

  test "emit/4 function" do
    client = self()
    {:ok, server} = EvalBackend.start_link()
    channels = ["ch0", "ch1"] |> Enum.map(&({server, &1}))
    YProcess.Backend.create(EvalBackend, channels)
    assert %{"ch0" => [], "ch1" => []} = EvalBackend.state(server)
    YProcess.Backend.join(EvalBackend, channels)
    assert %{"ch0" => [^client], "ch1" => [^client]} = EvalBackend.state(server)
    YProcess.Backend.emit(EvalBackend, channels, "message",
      fn channel, message ->
        {:message, channel, message}
      end)
    assert_receive {:message, {^server, "ch0"}, "message"}
    assert_receive {:message, {^server, "ch1"}, "message"}
    EvalBackend.stop(server)
  end
end
