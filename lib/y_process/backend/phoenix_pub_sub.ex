defmodule YProcess.Backend.PhoenixPubSub do
  @moduledoc """
  Simple implementation of channels using Phoenix PubSub.
  """
  use YProcess.Backend
  alias Phoenix.PubSub

  @doc """
  Creates a `channel` in `Phoenix.PubSub`. The channels don't need to be
  created in `Phoenix.PubSub` so this is just for completion. This function
  does nothing.
  """
  def create(_), do: :ok

  @doc """
  Deletes a `channel` in `Phoenix.PubSub`. The channels don't need to be
  deleted in `Phoenix.PubSub` so this is just for completion. This function
  does nothing.
  """
  def delete(_), do: :ok

  ##
  # Transforms a channel to a channel name understood by Phoenix.PubSub
  defp transform_name(channel) when is_binary(channel) do
    channel
  end
  defp transform_name(channel) do
    channel |> :erlang.phash2() |> Integer.to_string()
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
  The process that calls this function joins a `channel` in `Phoenix.PubSub`.
  `_pid` is ignored.
  """
  def join(channel, _pid) do
    channel_name = transform_name(channel)
    case get_app_name() do
      {:ok, name} ->
        PubSub.unsubscribe(name, channel_name)
        PubSub.subscribe(name, channel_name)
      error ->
        error
    end
  end

  @doc """
  The process that calls this function leaves a `channel` in `Phoenix.PubSub`.
  `_pid` is ignored.
  """
  def leave(channel, _pid) do
    channel_name = transform_name(channel)
    case get_app_name() do
      {:ok, name} ->
        PubSub.unsubscribe(name, channel_name)
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
        PubSub.broadcast(name, channel_name, message)
      error ->
        error
    end
  end
end
