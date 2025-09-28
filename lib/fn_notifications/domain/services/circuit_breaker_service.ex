defmodule FnNotifications.Domain.Services.CircuitBreakerService do
  @moduledoc """
  Domain service for circuit breaker pattern protecting external service calls.
  """

  use GenServer

  require Logger

  @type state :: :closed | :open | :half_open
  @type service_name :: atom()

  @initial_state %{
    state: :closed,
    failure_count: 0,
    last_failure: nil,
    success_count: 0,
    failure_threshold: 5,
    recovery_timeout: 30_000
  }

  def start_link(opts) do
    service_name = Keyword.fetch!(opts, :service_name)
    GenServer.start_link(__MODULE__, @initial_state, name: service_name)
  end

  @doc """
  Executes a function through the circuit breaker.
  """
  @spec call(service_name(), (-> any())) :: {:ok, any()} | {:error, String.t()}
  def call(service_name, fun) when is_function(fun, 0) do
    GenServer.call(service_name, {:call, fun})
  end

  @doc """
  Gets current circuit breaker state for monitoring.
  """
  @spec get_state(service_name()) :: map()
  def get_state(service_name) do
    GenServer.call(service_name, :get_state)
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun}, _from, state) do
    case should_allow_call?(state) do
      true ->
        result = execute_with_tracking(fun, state)
        new_state = update_state_from_result(state, result)
        {:reply, result, new_state}

      false ->
        Logger.warning("Circuit breaker OPEN - call rejected")
        {:reply, {:error, "Circuit breaker open"}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  ## Private Functions

  defp should_allow_call?(%{state: :closed}), do: true
  defp should_allow_call?(%{state: :half_open}), do: true

  defp should_allow_call?(%{state: :open, last_failure: last_failure, recovery_timeout: timeout}) do
    case last_failure do
      nil -> true
      timestamp ->
        time_since_failure = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
        time_since_failure > timeout
    end
  end

  defp execute_with_tracking(fun, _state) do
    try do
      result = fun.()
      {:ok, result}
    rescue
      error ->
        Logger.warning("Circuit breaker: Service call failed - #{inspect(error)}")
        {:error, "Service call failed: #{inspect(error)}"}
    catch
      :exit, reason ->
        Logger.warning("Circuit breaker: Service call exited - #{inspect(reason)}")
        {:error, "Service call exited: #{inspect(reason)}"}
    end
  end

  defp update_state_from_result(state, {:ok, _}) do
    new_state = next_state(state.state, true)
    %{state |
      state: new_state,
      failure_count: 0,
      success_count: state.success_count + 1,
      last_failure: nil
    }
  end

  defp update_state_from_result(state, {:error, _}) do
    new_failure_count = state.failure_count + 1

    new_state =
      if new_failure_count >= state.failure_threshold do
        next_state(state.state, false)
      else
        state.state
      end

    %{state |
      state: new_state,
      failure_count: new_failure_count,
      last_failure: DateTime.utc_now()
    }
  end

  # Circuit breaker state transitions
  defp next_state(:closed, false), do: :open
  defp next_state(:open, true), do: :half_open
  defp next_state(:half_open, true), do: :closed
  defp next_state(:half_open, false), do: :open
  defp next_state(state, _), do: state
end