defmodule YProcess.Backend.PhoenixPubSub do
  @moduledoc """
  Simple implementation of channels using Phoenix PubSub.
  """
  use YProcess.Backend

  @doc """
  Creates a `channel` in `Phoenix.PubSub`. The channels don't need to be
  created in `Phoenix.PubSub` so this is just for completion. This function
  does nothing.
  """
  def create(channel), do: :ok

  @doc """
  Deletes a `channel` in `Phoenix.PubSub`. The channels don't need to be
  deleted in `Phoenix.PubSub` so this is just for completion. This function
  does nothing.
  """
  def delete(channel), do: :ok

  ##
  # Transforms a channel to a channel name understood by Phoenix.PubSub
  defp transform_name(channel) when is_binary(channel) do
    channel
  end
  defp transform_name(channel) do
    :erlang.phash2(channel) |> Integer.to_string()
  end

  ##
  # Gets the app name.
  defp get_app_name do
    case Application.get_env(:y_process, :opts, []) do
      [] ->
        {:error, "Cannot find app name"}
      opts when is_list(opts) ->
        case Keyword.get(opts, :app_name, nil) do
          nil ->
            {:error, "Cannot find_app_name"}
          name ->
            {:ok, name}
        end
      _ ->
        {:error, "Cannot find app name"}
    end
  end

  @doc """
  The process with the `pid` joins a `channel` in `Phoenix.PubSub`.
  """
  def join(channel, pid) do
    channel_name = transform_name(channel)
    case get_app_name() do
      {:ok, name} ->
        Phoenix.Pubsub.subscribe(name, pid, channel_name)
      error ->
        error
    end
  end

  @doc """
  The process with the `pid` leaves a `channel` in `Phoenix.PubSub`.
  """
  def leave(channel, pid) do
    channel_name = transform_name(channel)
    case get_app_name() do
      {:ok, name} ->
        Phoenix.Pubsub.unsubscribe(name, pid, channel_name)
      error ->
        error
    end
  end

  @doc """
  Emits a `message` in a `Phoenix.PubSub` `channel`
  """
  def emit(channel, message) do
    channel_name = transform_name(channel)
    case get_app_name() do
      {:ok, name} ->
        Phoenix.Pubsub.broadcast(name, channel_name, message)
      error ->
        error
    end
  end
end
