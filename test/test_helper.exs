ExUnit.start()

defmodule EvalYProcess do
  use YProcess

  def init(fun) when is_function(fun, 0), do: fun.()
  def init(state), do: {:ok, state}

  def handle_call(:state, _from, state), do:
    {:reply, state, state}
  def handle_call(fun, from, state) when is_function(fun), do:
    fun.(from, state)
  def handle_call(message, from, fun) when is_function(fun), do:
    fun.(message, from, fun)

  def handle_cast(fun, state), do: fun.(state)

  def handle_event(channel, message, fun), do: fun.(channel, message)

  def handle_info(message, state) when is_function(message, 1), do:
    message.(state)
  def handle_info(message, fun) when is_function(fun, 1), do:
    fun.(message)
  def handle_info(message, fun) when is_function(fun, 2), do:
    fun.(message, fun)
end
