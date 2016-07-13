defmodule YProcess.Backend.PG2Test do
  use ExUnit.Case, async: true

  test "create/1" do
    channel = make_ref()
    assert :ok = YProcess.Backend.PG2.create(channel)
    assert [] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.delete(channel)
  end

  test "delete/1" do
    channel = make_ref()
    assert :ok = YProcess.Backend.PG2.create(channel)
    assert :ok = YProcess.Backend.PG2.delete(channel)
    assert {:error, {:no_such_group, ^channel}} = :pg2.get_members(channel)
  end

  test "join/2" do
    channel = make_ref()
    pid = self()
    assert :ok = YProcess.Backend.PG2.join(channel, pid)
    assert [^pid] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.join(channel, pid)
    assert [^pid] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.delete(channel)
  end

  test "leave/2" do
    channel = make_ref()
    pid = self()
    assert :ok = YProcess.Backend.PG2.join(channel, pid)
    assert [^pid] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.leave(channel, pid)
    assert [] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.delete(channel)
  end

  test "emit/2" do
    channel = make_ref()
    pid = self()
    assert :ok = YProcess.Backend.PG2.join(channel, pid)
    assert [^pid] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.emit(channel, "message")
    assert_receive "message"
    assert :ok = YProcess.Backend.PG2.leave(channel, pid)
    assert [] = :pg2.get_members(channel)
    assert :ok = YProcess.Backend.PG2.delete(channel)

  end
end
