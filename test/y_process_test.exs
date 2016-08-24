defmodule YProcessTest do
  use ExUnit.Case, async: true

  test "__using__" do
    defmodule Sample do
      use YProcess
    end

    assert Sample.init(:my_state) == {:ok, :my_state}
    assert Sample.ready(:joined, [], :my_state) == {:noreply, :my_state}
    assert catch_exit(Sample.handle_call(:my_call, {self, make_ref}, nil)) ==
      {:bad_call, :my_call}
    assert catch_exit(Sample.handle_cast(:my_cast, nil)) ==
      {:bad_cast, :my_cast}
    assert Sample.handle_info(:my_info, nil) == {:noreply, nil}
    assert catch_exit(Sample.handle_event(:channel, :message, nil)) ==
      {:bad_event, {:channel, :message}}
    assert Sample.terminate(:my_reason, nil) == :ok
    assert Sample.code_change(:vsn, :my_state, :extra) == {:ok, :my_state}
  end

  #############################################################################
  # YProcess.init/1 tests

  test "init {:ok, state}" do
    fun = fn -> {:ok, 0} end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, fun)
    assert YProcess.is_ready?(pid)
    assert YProcess.wait_ready(pid)
    assert YProcess.call(pid, :state) === 0
    assert :ok == YProcess.stop(pid)
  end

  test "init {:ok, state, timeout}" do
    parent = self()

    fun = fn ->
      timeout = fn :timeout ->
        send(parent, 1)
        {:noreply, 2}
      end
      {:ok, timeout, 0}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, fun)
    assert_receive 1, 200
    assert :ok == YProcess.stop(pid)
  end

  test "init {:ok, state, :hibernate}" do
    fun = fn ->
      {:ok, 0, :hibernate}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, fun)
    :timer.sleep(100)
    assert Process.info(pid, :current_function) ===
      {:current_function, {:erlang, :hibernate, 3}}
    assert YProcess.call(pid, :state) == 0
    assert :ok == YProcess.stop(pid)
  end

  test "init {:create, channels, state}" do
    parent = self()
    ref0 = make_ref()
    ref1 = make_ref()
    fun = fn ->
      {:create, [ref0, ref1], parent}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, fun)
    assert YProcess.wait_ready(pid)
    assert_receive {:ready, :created, [^ref0, ^ref1]}
    assert :ok == :pg2.join(ref0, self)
    assert :ok == :pg2.join(ref1, self)
    assert :ok == YProcess.stop(pid)
  end

  test "init {:join, channels, state}" do
    parent = self()
    ref0 = make_ref()
    ref1 = make_ref()
    fun = fn ->
      {:join, [ref0, ref1], parent}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, fun)
    assert YProcess.wait_ready(pid)
    assert_receive {:ready, :joined, [^ref0, ^ref1]}
    assert :ok == :pg2.join(ref0, self)
    assert :ok == :pg2.join(ref1, self)
    assert :ok == YProcess.stop(pid)
  end

  test "init :ignore" do
    _ = Process.flag(:trap_exit, true)
    fun = fn -> :ignore end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    assert :ignore == YProcess.start_link(EvalYProcess, fun, opts)
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, :normal}, 200
  end

  test "init {:stop, reason}" do
    _ = Process.flag(:trap_exit, true)
    fun = fn -> {:stop, :normal} end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    assert {:error, :normal} == YProcess.start_link(EvalYProcess, fun, opts)
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, :normal}, 200
  end

  test "init bad return" do
    _ = Process.flag(:trap_exit, true)
    fun = fn -> :error end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    error = YProcess.start_link(EvalYProcess, fun, opts)
    assert {:error, {:bad_return_value, :error}} = error
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, {:bad_return_value, :error}}, 200
  end

  test "init exit" do
    _ = Process.flag(:trap_exit, true)
    fun = fn -> exit(:normal) end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    assert {:error, :normal} == YProcess.start_link(EvalYProcess, fun, opts)
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, :normal}, 200
  end

  test "init error" do
    _ = Process.flag(:trap_exit, true)
    {:current_stacktrace, stack} = Process.info(self, :current_stacktrace)
    fun = fn -> :erlang.raise(:error, :oops, stack) end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    error = YProcess.start_link(EvalYProcess, fun, opts)
    assert {:error, {:oops, ^stack}} = error
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, {:oops, ^stack}}, 200
  end

  test "init throw" do
    _ = Process.flag(:trap_exit, true)
    {:current_stacktrace, stack} = Process.info(self, :current_stacktrace)
    fun = fn -> :erlang.raise(:throw, :oops, stack) end
    name = :"#{inspect make_ref}"
    opts = [name: name]
    error = YProcess.start_link(EvalYProcess, fun, opts)
    assert {:error, {{:nocatch, :oops}, ^stack}} = error
    assert nil == Process.whereis(name)
    assert_receive {:EXIT, _, {{:nocatch, :oops}, ^stack}}, 200
  end

  #############################################################################
  # YProcess.handle_call/3 tests

  test "handle_call {:reply, reply, state}" do
    fun = fn (_, n) -> {:reply, n, n + 1} end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.wait_ready(pid)
    assert YProcess.call(pid, fun) == 1
    assert YProcess.call(pid, :state) == 2
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:reply, reply, state, timeout}" do
    parent = self()
    fun = fn(_, n) ->
      timeout = fn :timeout ->
        send(parent, {:timeout, n})
        {:noreply, n + 1}
      end
      {:reply, n, timeout, 0}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.call(pid, fun) == 1
    assert_receive {:timeout, 1}, 500
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:noreply, state}" do
    fun = fn(from, n) ->
      YProcess.reply(from, n)
      {:noreply, n + 1}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.wait_ready(pid)
    assert YProcess.call(pid, fun) == 1
    assert YProcess.call(pid, :state) == 2
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:noreply, state, timeout}" do
    parent = self()
    fun = fn(from, n) ->
      timeout = fn :timeout ->
        send(parent, {:timeout, n})
        {:noreply, n + 1}
      end
      YProcess.reply(from, n)
      {:noreply, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.call(pid, fun) == 1
    assert_receive {:timeout, 1}, 500
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:create, channels, new_state}" do
    fun = fn (from, channels)->
      channel = make_ref()
      YProcess.reply(from, channel)
      {:create, [channel], [channel | channels]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    assert YProcess.wait_ready(pid)
    channel = YProcess.call(pid, fun)
    _ = YProcess.call(pid, :state)
    assert is_reference(channel)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rcreate, channels, reply, new_state}" do
    fun = fn (_, channels)->
      channel = make_ref()
      {:rcreate, [channel], channel, [channel | channels]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    channel = YProcess.call(pid, fun)
    assert is_reference(channel)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:create, channels, new_state, timeout}" do
    parent = self()
    fun = fn (from, channels) ->
      channel = make_ref()
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, [channel | channels]}
      end
      YProcess.reply(from, channel)
      {:create, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    channel = YProcess.call(pid, fun)
    assert is_reference(channel)
    assert_receive {:timeout, ^channel}, 500
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:rcreate, channels, reply, new_state, timeout}" do
    parent = self()
    fun = fn (_, channels) ->
      channel = make_ref()
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, [channel | channels]}
      end
      {:rcreate, [channel], channel, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    channel = YProcess.call(pid, fun)
    assert is_reference(channel)
    assert_receive {:timeout, ^channel}, 500
    assert :ok = YProcess.stop(pid)
  end

  test "handle_call {:delete, channels, new_state}" do
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn (from, [channel])->
      YProcess.reply(from, :ok)
      {:delete, [channel], []}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    :ok = YProcess.call(pid, fun)
    _ = YProcess.call(pid, :state)
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rdelete, channels, reply, new_state}" do
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn (_, [channel])->
      {:rdelete, [channel], channel, []}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    channel = YProcess.call(pid, fun)
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:delete, channels, new_state, timeout}" do
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    parent = self()
    fun = fn (from, [channel])->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, []}
      end
      YProcess.reply(from, :ok)
      {:delete, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert :ok = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rdelete, channels, reply, new_state, timeout}" do
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    parent = self()
    fun = fn (_, [channel])->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, []}
      end
      {:rdelete, [channel], channel, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    channel = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:join, channels, new_state}" do
    channel = make_ref()
    fun = fn (from, _)->
      YProcess.reply(from, :ok)
      {:join, [channel], nil}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.call(pid, fun)
     _ = YProcess.call(pid, :state)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rjoin, channels, reply, new_state}" do
    channel = make_ref()
    fun = fn (_, _)->
      {:rjoin, [channel], channel, nil}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    assert ^channel = YProcess.call(pid, fun)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:join, channels, new_state, timeout}" do
    parent = self()
    channel = make_ref()
    fun = fn (from, _)->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      YProcess.reply(from, :ok)
      {:join, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rjoin, channels, reply, new_state, timeout}" do
    parent = self()
    channel = make_ref()
    fun = fn (_, _)->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      {:rjoin, [channel], channel, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert ^channel = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:leave, channels, new_state}" do
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end
    fun = fn (from, _)->
      YProcess.reply(from, :ok)
      {:leave, [channel], nil}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.call(pid, fun)
     _ = YProcess.call(pid, :state)
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rleave, channels, reply, new_state}" do
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end
    fun = fn (_, _)->
      {:rleave, [channel], :ok, nil}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.call(pid, fun)
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:leave, channels, new_state, timeout}" do
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    parent = self()
    fun = fn (from, _)->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      YProcess.reply(from, :ok)
      {:leave, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert :ok = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:rleave, channels, reply, new_state, timeout}" do
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    parent = self()
    fun = fn (_, _)->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      {:rleave, [channel], :ok, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert :ok = YProcess.call(pid, fun)
    assert_receive {:timeout, ^channel}, 500
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_call {:emit, channels, message, mod_state}" do
    parent = self()
    channel = make_ref

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn (from, _) ->
      YProcess.reply(from, :ok)
      {:emit, [channel], {:message, channel}, nil}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:remit, channels, message, reply, mod_state}" do
    parent = self()
    channel = make_ref

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn (_, _) ->
      {:remit, [channel], {:message, channel}, :ok, nil}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:emit, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn (from, _) ->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      YProcess.reply(from, :ok)
      {:emit, [channel], {:message, channel}, timeout, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    assert_receive {:timeout, ^channel}, 500
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:remit, channels, message, reply, mod_state, timeout}" do
    parent = self()
    channel = make_ref

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn (_, _) ->
      timeout = fn :timeout ->
        send(parent, {:timeout, channel})
        {:noreply, nil}
      end
      {:remit, [channel], {:message, channel}, :ok, timeout, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    assert_receive {:timeout, ^channel}, 500
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:emit_ack, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn {:DELIVERED, _, ^channel, {:message, ^channel}} = message ->
        send(parent, message)
        {:noreply, nil}
      end
      {:create, [channel], ack}
    end

    emit = fn(from, ack) ->
      YProcess.reply(from, :ok)
      {:emit_ack, [channel], {:message, channel}, ack}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:received, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:remit_ack, channels, message, reply, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn {:DELIVERED, _, ^channel, {:message, ^channel}} = message ->
        send(parent, message)
        {:noreply, nil}
      end
      {:create, [channel], ack}
    end

    emit = fn(_, ack) ->
      {:remit_ack, [channel], {:message, channel}, :ok, ack}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:received, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:emit_ack, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn
        {:DELIVERED, _, ^channel, {:message, ^channel}} = message, fun ->
          send(parent, message)
          {:noreply, fun, 0}
        :timeout, fun ->
          send(parent, {:timeout, channel})
          {:noreply, fun}
      end
      {:create, [channel], ack}
    end

    emit = fn(from, ack) ->
      YProcess.reply(from, :ok)
      {:emit_ack, [channel], {:message, channel}, ack, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:received, ^channel, ^message}, 200
    assert_receive {:timeout, ^channel}, 500
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:remit_ack, channels, message, reply, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn
        {:DELIVERED, _, ^channel, {:message, ^channel}} = message, fun ->
          send(parent, message)
          {:noreply, fun, 0}
        :timeout, fun ->
          send(parent, {:timeout, channel})
          {:noreply, fun}
      end
      {:create, [channel], ack}
    end

    emit = fn(_, ack) ->
      {:remit_ack, [channel], {:message, channel}, :ok, ack, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.call(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:received, ^channel, ^message}, 200
    assert_receive {:timeout, ^channel}, 500
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_call {:stop, reason, mod_state}" do
    _ = Process.flag(:trap_exit, true)
    stop = fn (from, state) ->
      YProcess.reply(from, :ok)
      {:stop, :normal, state}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.call(pid, stop)
    assert_receive {:EXIT, ^pid, :normal}, 200
  end

  test "handle_call {:stop, reason, reply, mod_state}" do
    _ = Process.flag(:trap_exit, true)
    stop = fn (_, s) -> {:stop, :normal, :ok, s} end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.call(pid, stop)
    assert_receive {:EXIT, ^pid, :normal}, 200
  end

  #############################################################################
  # YProcess.handle_cast/2 tests

  test "handle_cast {:noreply, mod_state}" do
    fun = fn(n) ->
      {:noreply, n + 1}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.cast(pid, fun)
    assert YProcess.call(pid, :state) == 2
    assert :ok = YProcess.stop(pid)
  end

  test "handle_cast {:noreply, mod_state, timeout}" do
    parent = self()
    fun = fn(_) ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:noreply, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.cast(pid, fun)
    assert_receive :timeout, 200
    assert :ok = YProcess.stop(pid)
  end

  test "handle_cast {:create, channels, mod_state}" do
    channel = make_ref()
    create = fn ([])-> {:create, [channel], [channel]} end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.cast(pid, create)
    assert [^channel] = YProcess.call(pid, :state)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_cast {:create, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    create = fn ([])->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:create, [channel], timeout, 0}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    assert :ok = YProcess.cast(pid, create)
    assert_receive :timeout, 200
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_cast {:delete, channels, mod_state}" do
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn ([channel])->
      {:delete, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.cast(pid, fun)
    assert [^channel] = YProcess.call(pid, :state)
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_cast {:delete, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn ([channel])->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:delete, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert :ok = YProcess.cast(pid, fun)
    assert_receive :timeout, 200
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 

  end

  test "handle_cast {:join, channels, mod_state}" do
    channel = make_ref()
    fun = fn _ ->
      {:join, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.cast(pid, fun)
    assert [^channel] = YProcess.call(pid, :state)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid)  
  end

  test "handle_cast {:join, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    fun = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:join, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.cast(pid, fun)
    assert_receive :timeout, 200
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid)  
  end

  test "handle_cast {:leave, channels, mod_state}" do
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    leave = fn _ ->
      {:leave, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    assert :ok = YProcess.cast(pid, leave)
    assert [^channel] = YProcess.call(pid, :state)
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid)
  end

  test "handle_cast {:leave, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    leave = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:leave, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert :ok = YProcess.cast(pid, leave)
    assert_receive :timeout, 200
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid)
  end

  test "handle_cast {:emit, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn _ ->
      {:emit, [channel], {:message, channel}, nil}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.cast(producer, emit)
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_cast {:emit, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      {:emit, [channel], {:message, channel}, timeout, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.cast(producer, emit)
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert_receive :timeout, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_cast {:emit_ack, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn {:DELIVERED, _, ^channel, {:message, ^channel}} = message ->
        send(parent, message)
        {:noreply, nil}
      end
      {:create, [channel], ack}
    end

    emit = fn(ack) ->
      {:emit_ack, [channel], {:message, channel}, ack}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.cast(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:received, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer) 
  end

  test "handle_cast {:emit_ack, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn
        {:DELIVERED, _, ^channel, {:message, ^channel}} = message, fun ->
          send(parent, message)
          {:noreply, fun, 0}
        :timeout, fun ->
          send(parent, {:timeout, channel})
          {:noreply, fun}
      end
      {:create, [channel], ack}
    end

    emit = fn(ack) ->
      {:emit_ack, [channel], {:message, channel}, ack, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    assert :ok = YProcess.cast(producer, emit)
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:timeout, ^channel}, 500
    assert_receive {:received, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_cast {:stop, reason, mod_state}" do
    _ = Process.flag(:trap_exit, true)
    stop = &({:stop, :normal, &1})

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.cast(pid, stop)
    assert_receive {:EXIT, ^pid, :normal}, 200
  end

  #############################################################################
  # YProcess.handle_info/2 tests

  test "handle_info {:noreply, mod_state}" do
    parent = self()
    fun = fn(n) ->
      send(parent, :continue)
      {:noreply, n + 1}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, 1)
    assert YProcess.wait_ready(pid)
    send(pid, fun)
    assert_receive :continue, 200
    assert YProcess.call(pid, :state) == 2
    assert :ok = YProcess.stop(pid)
  end

  test "handle_info {:noreply, mod_state, timeout}" do
    parent = self()
    fun = fn(_) ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:noreply, timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    send(pid, fun)
    assert_receive :continue, 200
    assert :ok = YProcess.cast(pid, fun)
    assert_receive :timeout, 200
    assert :ok = YProcess.stop(pid)
  end

  test "handle_info {:create, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    create = fn ([])->
      send(parent, :continue)
      {:create, [channel], [channel]}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    assert YProcess.wait_ready(pid)
    send(pid, create)
    assert_receive :continue, 200
    assert [^channel] = YProcess.call(pid, :state)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_info {:create, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    create = fn ([])->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:create, [channel], timeout, 0}
    end

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, [])
    send(pid, create)
    assert_receive :continue, 200
    assert_receive :timeout, 200
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_info {:delete, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn ([channel])->
      send(parent, :continue)
      {:delete, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    send(pid, fun)
    assert_receive :continue, 200
    assert [^channel] = YProcess.call(pid, :state)
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_info {:delete, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:create, [channel], [channel]}
    end

    fun = fn ([channel])->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:delete, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    send(pid, fun)
    assert_receive :continue, 200
    assert_receive :timeout, 200
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(pid) 
  end

  test "handle_info {:join, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    fun = fn _ ->
      send(parent, :continue)
      {:join, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    send(pid, fun)
    assert_receive :continue, 200
    assert [^channel] = YProcess.call(pid, :state)
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid)  
  end

  test "handle_info {:join, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    fun = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:join, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    send(pid, fun)
    assert_receive :continue, 200
    assert_receive :timeout, 200
    assert :pg2.which_groups |> Enum.member?(channel)
    assert :pg2.get_members(channel) |> Enum.member?(pid)
    assert :ok = YProcess.stop(pid)  
  end

  test "handle_info {:leave, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    leave = fn _ ->
      send(parent, :continue)
      {:leave, [channel], [channel]}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(pid)
    send(pid, leave)
    assert_receive :continue, 200
    assert [^channel] = YProcess.call(pid, :state)
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid)
  end

  test "handle_info {:leave, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    init = fn ->
      {:join, [channel], nil}
    end

    leave = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:leave, [channel], timeout, 0}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init)
    send(pid, leave)
    assert_receive :continue, 200
    assert_receive :timeout, 200
    assert not (:pg2.get_members(channel) |> Enum.member?(pid))
    assert :ok = YProcess.stop(pid)
  end

  test "handle_info {:emit, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn _ ->
      send(parent, :continue)
      {:emit, [channel], {:message, channel}, nil}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    send(producer, emit)
    assert_receive :continue, 200
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_info {:emit, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      {:create, [channel], nil}
    end

    emit = fn _ ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      send(parent, :continue)
      {:emit, [channel], {:message, channel}, timeout, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    send(producer, emit)
    assert_receive :continue, 200
    assert_receive {:received, ^channel, {:message, ^channel}}, 200
    assert_receive :timeout, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_info {:emit_ack, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn {:DELIVERED, _, ^channel, {:message, ^channel}} = message ->
        send(parent, message)
        {:noreply, nil}
      end
      {:create, [channel], ack}
    end

    emit = fn(ack) ->
      send(parent, :continue)
      {:emit_ack, [channel], {:message, channel}, ack}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert YProcess.wait_ready(producer)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(consumer)
    assert :ok = YProcess.call(consumer, join)
    send(producer, emit)
    assert_receive :continue, 200
    message = {:message, channel}
    assert_receive {:received, ^channel, ^message}, 200
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer) 
  end

  test "handle_info {:emit_ack, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()

    # Producer
    init = fn ->
      ack = fn
        {:DELIVERED, _, ^channel, {:message, ^channel}} = message, fun ->
          send(parent, message)
          {:noreply, fun, 0}
        :timeout, fun ->
          send(parent, {:timeout, channel})
          {:noreply, fun}
      end
      {:create, [channel], ack}
    end

    emit = fn(ack) ->
      send(parent, :continue)
      {:emit_ack, [channel], {:message, channel}, ack, 0}
    end

    # Consumer
    join = fn (_, _) ->
      recv = fn (channel, message) ->
        send(parent, {:received, channel, message})
        {:noreply, nil}
      end
      {:rjoin, [channel], :ok, recv}
    end

    assert {:ok, producer} = YProcess.start_link(EvalYProcess, init)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, nil)
    assert :ok = YProcess.call(consumer, join)
    send(producer, emit)
    assert_receive :continue, 200
    message = {:message, channel}
    assert_receive {:DELIVERED, _, ^channel, ^message}, 200
    assert_receive {:timeout, ^channel}, 500
    assert_receive {:received, ^channel, ^message}, 200
    assert :ok = YProcess.stop(consumer)
    assert :ok = YProcess.stop(producer)
  end

  test "handle_info {:stop, reason, mod_state}" do
    _ = Process.flag(:trap_exit, true)
    stop = &({:stop, :normal, &1})

    assert {:ok, pid} = YProcess.start_link(EvalYProcess, nil)
    assert YProcess.wait_ready(pid)
    send(pid, stop)
    assert_receive {:EXIT, ^pid, :normal}, 200
  end

  #############################################################################
  # YProcess.handle_event/3 tests

  defp start_producer(channel) do
    init_producer = fn ->
      emit = fn (message, _, s) ->
        {:remit, [channel], message, :ok, s}
      end
      {:create, [channel], emit}
    end
    assert {:ok, pid} = YProcess.start_link(EvalYProcess, init_producer)
    pid
  end

  defp stop_producer(pid) do
    assert :ok = YProcess.stop(pid)
  end

  defp trigger_event(pid, message) do
    assert :ok = YProcess.call(pid, message)
  end

  test "handle_event {:noreply, mod_state}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      recv = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:noreply, nil}
      end
      {:join, [channel], recv}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert YProcess.call(consumer, :state) == nil
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:noreply, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      recv = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:noreply, timeout, 0}
      end
      {:join, [channel], recv}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive :timeout, 200
    assert YProcess.call(consumer, :state) == nil
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:create, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    # Consumer
    init_consumer = fn ->
      create = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:create, [message], nil}
      end
      {:join, [channel], create}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    second_channel = make_ref()
    trigger_event(producer, second_channel)
    assert_receive {:message, ^channel, ^second_channel}, 200
    assert YProcess.call(consumer, :state) == nil
    assert :pg2.which_groups |> Enum.member?(second_channel)
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:create, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    # Consumer
    init_consumer = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      create = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:create, [message], timeout, 0}
      end
      {:join, [channel], create}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    second_channel = make_ref()
    trigger_event(producer, second_channel)
    assert_receive {:message, ^channel, ^second_channel}, 200
    assert_receive :timeout, 200
    assert YProcess.call(consumer, :state) == nil
    assert :pg2.which_groups |> Enum.member?(second_channel)
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:delete, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      delete = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:delete, [channel], nil}
      end
      {:join, [channel], delete}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert YProcess.call(consumer, :state) == nil
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:delete, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      delete = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:delete, [channel], timeout, 0}
      end
      {:join, [channel], delete}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive :timeout, 200
    assert YProcess.call(consumer, :state) == nil
    assert not (:pg2.which_groups |> Enum.member?(channel))
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:join, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    # Consumer
    init_consumer = fn ->
      join = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:join, [message], nil}
      end
      {:join, [channel], join}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    second_channel = make_ref()
    trigger_event(producer, second_channel)
    assert_receive {:message, ^channel, ^second_channel}, 200
    assert YProcess.call(consumer, :state) == nil
    assert :pg2.get_members(second_channel)
            |> Enum.member?(consumer)
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:join, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    # Consumer
    init_consumer = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      join = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:join, [message], timeout, 0}
      end
      {:join, [channel], join}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    second_channel = make_ref()
    trigger_event(producer, second_channel)
    assert_receive {:message, ^channel, ^second_channel}, 200
    assert_receive :timeout, 200
    assert YProcess.call(consumer, :state) == nil
    assert :pg2.get_members(second_channel)
            |> Enum.member?(consumer)
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_leave {:leave, channels, mod_state}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      leave = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:leave, [channel], nil}
      end
      {:join, [channel], leave}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert YProcess.call(consumer, :state) == nil
    assert not (:pg2.get_members(channel)
                |> Enum.member?(consumer))
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  test "handle_event {:leave, channels, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      leave = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:leave, [channel], timeout, 0}
      end
      {:join, [channel], leave}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive :timeout, 200
    assert YProcess.call(consumer, :state) == nil
    assert not (:pg2.get_members(channel)
                |> Enum.member?(consumer))
    assert :ok = YProcess.stop(consumer)
    stop_producer(producer)
  end

  defp start_consumer(channel, parent) do
    init_consumer = fn ->
      recv = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:noreply, nil}
      end
      {:join, [channel], recv}
    end
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    consumer
  end

  defp stop_consumer(consumer) do
    assert :ok = YProcess.stop(consumer)
  end

  test "handle_event {:emit, channels, message, mod_state}" do
    parent = self()
    channel = make_ref()
    second_channel = make_ref()
    message = :trigger
    # Forwarder
    init_forwarder = fn ->
      emit = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:emit, [second_channel], message, nil}
      end
      {:join, [channel], emit}
    end

    producer = start_producer(channel)
    consumer = start_consumer(second_channel, parent)
    assert {:ok, forwarder} = YProcess.start_link(EvalYProcess, init_forwarder)
    assert is_function(YProcess.call(forwarder, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive {:message, ^second_channel, ^message}, 200
    assert YProcess.call(forwarder, :state) == nil
    assert :ok = YProcess.stop(forwarder)
    stop_consumer(consumer)
    stop_producer(producer)
  end

  test "handle_event {:emit, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    second_channel = make_ref()
    message = :trigger
    # Forwarder
    init_forwarder = fn ->
      timeout = fn :timeout ->
        send(parent, :timeout)
        {:noreply, nil}
      end
      emit = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:emit, [second_channel], message, timeout, 0}
      end
      {:join, [channel], emit}
    end

    producer = start_producer(channel)
    consumer = start_consumer(second_channel, parent)
    assert {:ok, forwarder} = YProcess.start_link(EvalYProcess, init_forwarder)
    assert is_function(YProcess.call(forwarder, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive :timeout, 200
    assert_receive {:message, ^second_channel, ^message}, 200
    assert YProcess.call(forwarder, :state) == nil
    assert :ok = YProcess.stop(forwarder)
    stop_consumer(consumer)
    stop_producer(producer)
  end

  test "handle_event {:emit_ack, channels, message, ack_timeout, mod_state}" do
    parent = self()
    channel = make_ref()
    second_channel = make_ref()
    message = :trigger
    # Forwarder
    init_forwarder = fn ->
      ack = fn {:DELIVERED, _, ^second_channel, _} = message ->
        send(parent, message)
        {:noreply, nil}
      end
      emit = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:emit_ack, [second_channel], message, ack}
      end
      {:join, [channel], emit}
    end

    producer = start_producer(channel)
    consumer = start_consumer(second_channel, parent)
    assert {:ok, forwarder} = YProcess.start_link(EvalYProcess, init_forwarder)
    assert is_function(YProcess.call(forwarder, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive {:DELIVERED, _, ^second_channel, ^message}, 200
    assert_receive {:message, ^second_channel, ^message}, 200
    assert YProcess.call(forwarder, :state) == nil
    assert :ok = YProcess.stop(forwarder)
    stop_consumer(consumer)
    stop_producer(producer)
  end

  test "handle_event {:emit_ack, channels, message, mod_state, timeout}" do
    parent = self()
    channel = make_ref()
    second_channel = make_ref()
    message = :trigger
    # Forwarder
    init_forwarder = fn ->
      ack = fn
        {:DELIVERED, _, ^second_channel, _} = message, fun ->
          send(parent, message)
          {:noreply, fun, 0}
        :timeout, fun ->
          send(parent, :timeout)
          {:noreply, fun}
      end
      emit = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:emit_ack, [second_channel], message, ack, 0}
      end
      {:join, [channel], emit}
    end

    producer = start_producer(channel)
    consumer = start_consumer(second_channel, parent)
    assert {:ok, forwarder} = YProcess.start_link(EvalYProcess, init_forwarder)
    assert is_function(YProcess.call(forwarder, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive :timeout, 200
    assert_receive {:message, ^second_channel, ^message}, 200
    assert_receive {:DELIVERED, _, ^second_channel, ^message}, 200
    assert :ok = YProcess.stop(forwarder)
    stop_consumer(consumer)
    stop_producer(producer)
  end

  test "handle_event {:stop, reason, mod_state}" do
    _ = Process.flag(:trap_exit, true)
    parent = self()
    channel = make_ref()
    message = :trigger
    # Consumer
    init_consumer = fn ->
      stop = fn(channel, message) ->
        send(parent, {:message, channel, message})
        {:stop, :normal, nil}
      end
      {:join, [channel], stop}
    end
    producer = start_producer(channel)
    assert {:ok, consumer} = YProcess.start_link(EvalYProcess, init_consumer)
    assert is_function(YProcess.call(consumer, :state), 2)
    trigger_event(producer, message)
    assert_receive {:message, ^channel, ^message}, 200
    assert_receive {:EXIT, ^consumer, :normal}, 200
    stop_producer(producer)
  end
end
