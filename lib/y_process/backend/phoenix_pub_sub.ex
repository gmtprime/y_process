defmodule YProcess.Backend.PhoenixPubSub do
  @moduledoc """
  Simple implementation of channels using Phoenix PubSub.
  """
  use YProcess.Backend
  alias Phoenix.PubSub

  @name YProcess.PubSub

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
    Application.get_env(:y_process, :name, @name)
  end

  @doc """
  The process that calls this function joins a `channel` in `Phoenix.PubSub`.
  `_pid` is ignored.
  """
  def join(channel, _pid) do
    channel_name = transform_name(channel)
    name = get_app_name()
    PubSub.unsubscribe(name, channel_name)
    PubSub.subscribe(name, channel_name)
  end

  @doc """
  The process that calls this function leaves a `channel` in `Phoenix.PubSub`.
  `_pid` is ignored.
  """
  def leave(channel, _pid) do
    channel_name = transform_name(channel)
    name = get_app_name()
    PubSub.unsubscribe(name, channel_name)
  end

  @doc """
  Emits a `message` in a `Phoenix.PubSub` `channel`
  """
  def emit(channel, message) do
    channel_name = transform_name(channel)
    name = get_app_name()
    PubSub.broadcast(name, channel_name, message)
  end
end

defmodule YProcess.PhoenixPubSub do
  @moduledoc """
  Helper functions to start a `Phoenix.PubSub` supervisor.
  """

  @name YProcess.PubSub

  @doc """
  Starts Phoenix.PubSub supervisor.
  """
  def start_link do
    name = Application.get_env(:y_process, :name, @name)
    module = Application.get_env(:y_process, :adapter, Phoenix.PubSub.PG2)
    options = Application.get_env(:y_process, :options, [])
    module.start_link(name, options)
  end

  @doc """
  Stops the `supervisor`.
  """
  def stop(supervisor) do
    module = Application.get_env(:y_process, :adapter, Phoenix.PubSub.PG2)
    module.stop(supervisor)
  end
end
