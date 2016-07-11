defmodule YProcess.Backend do
  @moduledoc """
  Behaviour to implement backends for the communication between `YProcess`es.
  """

  @doc """
  Callback to create a `channel`.

  Returns `:ok` when the channel has been created succesfully.

  Returns `{:error, reason}` when the channel couldn't be created.
  """
  @callback create(channel) :: :ok | {:error, reason}
    when channel: YProcess.channel, reason: term

  @doc """
  Callback to delete a `channel`.

  Returns `:ok` when the channel has been deleted succesfully.

  Returns `{:error, reason}` when the channel couldn't be deleted.
  """
  @callback delete(channel) :: :ok | {:error, reason}
    when channel: YProcess.channel, reason: term

  @doc """
  Callback used to make a process with `pid` a `channel`.

  Returns `:ok` when the process joins the channel successfully.

  Returns `{:error, reason}` when the process couldn't join the channel.
  """
  @callback join(channel, pid) :: :ok | {:error, reason}
    when channel: YProcess.channel, reason: term

  @doc """
  Callback used to make a process with `pid` leave a `channel`.

  Returns `:ok` when the process leaves the channel successfully.

  Returns `{:error, reason}` when the process couldn't leave the channel.
  """
  @callback leave(channel, pid) :: :ok | {:error, reason}
    when channel: YProcess.channel, reason: term

  @doc """
  Callback used to send a `message` to a `channel`.

  Returns `:ok` when the message is sent.

  Returns `{:error, reason}` when the message couldn't be sent.
  """
  @callback emit(channel, message) :: :ok | {:error, reason}
    when channel: YProcess.channel, message: term, reason: term

  defmacro __using__(_) do
    quote do
      @behaviour YProcess.Backend

      def create(channel), do: {:error, {:bad_create, channel}}

      def delete(channel), do: {:error, {:bad_delete, channel}}

      def join(channel, _), do: {:error, {:bad_join, channel}}

      def leave(channel, _), do: {:error, {:bad_leave, channel}}

      def emit(channel, _), do: {:error, {:bad_emit, channel}}

      defoverridable [create: 1, delete: 1, join: 2, leave: 2, emit: 2]
    end
  end

  @doc """
  Creates `channels` using a backend `module`.
  """
  @spec create(module, channels) :: :ok | :no_return
    when channels: YProcess.channels
  def create(module, channels) do
    general_helper(channels, {module, :create, []})
  end

  @doc """
  Deletes `channels` using a backend `module`.
  """
  @spec delete(module, channels) :: :ok | :no_return
    when channels: YProcess.channels
  def delete(module, channels) do
    general_helper(channels, {module, :delete, []})
  end

  @doc """
  Joins the `channels` using a backend `module`.
  """
  @spec join(module, channels) :: :ok | :no_return
    when channels: YProcess.channels
  def join(module, channels) do
    general_helper(channels, {module, :join, [self()]})
  end

  @doc """
  Leaves the `channels` using a backend `module`.
  """
  @spec leave(module, channels) :: :ok | :no_return
    when channels: YProcess.channels
  def leave(module, channels) do
    general_helper(channels, {module, :leave, [self()]})
  end

  @doc """
  Emits messages. Uses a backend `module` to send a `message` to a list of
  `channels`.
  """
  @spec emit(module, channels, message, (channel, message -> term)) ::
    :ok | :no_return
      when channel: YProcess.channel, channels: YProcess.channels,
           message: term
  def emit(_, [], _, _), do: :ok
  def emit(module, [channel | channels], message, transform) do
    transformed = transform.(channel, message)
    case apply(module, :emit, [channel, transformed]) do
      :ok -> emit(module, channels, message, transform)
      error -> exit(error)
    end
  end

  ##
  # Helper function for operations with channels.
  defp general_helper([], _), do: :ok
  defp general_helper([channel | channels], {mod, fun, args} = mfa) do
    case apply(mod, fun, [channel | args]) do
      :ok -> general_helper(channels, mfa)
      error -> exit(error)
    end
  end
end
