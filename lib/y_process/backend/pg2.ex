defmodule YProcess.Backend.PG2 do
  @moduledoc """
  Simple implementation of channels using PG2's process groups.
  """
  use YProcess.Backend

  @doc """
  Creates a `channel` in `:pg2`.
  """
  def create(channel) do
    :pg2.create(channel)
  end

  @doc """
  Deletes a `channel` in `:pg2`
  """
  def delete(channel) do
    :pg2.delete(channel)
  end

  @doc """
  The process with the `pid` joins a `channel` in `:pg2`.
  """
  def join(channel, pid) do
    create(channel)
    is_subscribed? = channel |> :pg2.get_members |> Enum.member?(pid)
    if is_subscribed?, do: :ok, else: do_join(channel, pid)
  end

  ##
  # The process with the `pid` joins a `channel` in `:pg2`.
  defp do_join(channel, pid) do
    case :pg2.join(channel, pid) do
      :ok -> :ok
      {:error, reason} ->
        {:error, {"Cannot join channel", channel, reason}}
    end
  end

  @doc """
  The process with the `pid` leaves a `channel` in `:pg2`.
  """
  def leave(channel, pid) do
    _ = :pg2.leave(channel, pid)
    :ok
  end

  @doc """
  Emits a `message` in a `channel`.
  """
  def emit(channel, message) do
    _ = channel
     |> :pg2.get_members
     |> Enum.map(&(spawn(fn -> send &1, message end)))
    :ok
  end
end
