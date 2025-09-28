defmodule FnNotifications.Infrastructure.Health.HealthCheckService do
  @moduledoc """
  Health check service for monitoring system and dependency health.
  Provides endpoints for liveness and readiness probes.
  """

  use GenServer
  require Logger

  @type health_status :: :healthy | :unhealthy | :degraded
  @type check_result :: %{
    name: String.t(),
    status: health_status(),
    message: String.t(),
    last_checked: DateTime.t(),
    duration_ms: non_neg_integer()
  }

  @type state :: %{
    checks: map(),
    last_full_check: DateTime.t() | nil
  }

  @check_interval 30_000  # 30 seconds
  @timeout 5_000          # 5 seconds per check

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current health status of all components.
  """
  @spec get_health() :: {:ok, map()} | {:error, String.t()}
  def get_health do
    GenServer.call(__MODULE__, :get_health, 10_000)
  end


  @doc """
  Forces a health check run immediately.
  """
  @spec force_check() :: :ok
  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Schedule initial health check
    Process.send_after(self(), :run_health_checks, 1_000)

    state = %{
      checks: %{},
      last_full_check: nil
    }

    Logger.info("HealthCheckService started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    overall_status = calculate_overall_status(state.checks)

    health_response = %{
      overall_status: overall_status,
      last_checked: state.last_full_check,
      checks: state.checks,
      system_info: get_system_info()
    }

    {:reply, {:ok, health_response}, state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    send(self(), :run_health_checks)
    {:noreply, state}
  end

  @impl true
  def handle_info(:run_health_checks, state) do
    Logger.debug("Running health checks")

    checks = run_all_checks()
    updated_state = %{state |
      checks: checks,
      last_full_check: DateTime.utc_now()
    }

    # Schedule next check
    Process.send_after(self(), :run_health_checks, @check_interval)

    {:noreply, updated_state}
  end

  ## Private Functions

  defp run_all_checks do
    checks = [
      {"database", &check_database/0},
      {"kafka", &check_kafka/0},
      {"redis", &check_redis/0},
      {"twilio", &check_twilio/0},
      {"email_service", &check_email_service/0},
      {"circuit_breakers", &check_circuit_breakers/0},
      {"bulkhead_pools", &check_bulkhead_pools/0}
    ]

    Enum.into(checks, %{}, fn {name, check_func} ->
      {name, run_single_check(name, check_func)}
    end)
  end

  defp run_single_check(name, check_func) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case Task.await(Task.async(check_func), @timeout) do
        :ok ->
          duration = System.monotonic_time(:millisecond) - start_time
          %{
            name: name,
            status: :healthy,
            message: "OK",
            last_checked: DateTime.utc_now(),
            duration_ms: duration
          }

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          %{
            name: name,
            status: :unhealthy,
            message: "Error: #{reason}",
            last_checked: DateTime.utc_now(),
            duration_ms: duration
          }
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        %{
          name: name,
          status: :unhealthy,
          message: "Exception: #{inspect(error)}",
          last_checked: DateTime.utc_now(),
          duration_ms: duration
        }
    catch
      :exit, {:timeout, _} ->
        %{
          name: name,
          status: :unhealthy,
          message: "Timeout after #{@timeout}ms",
          last_checked: DateTime.utc_now(),
          duration_ms: @timeout
        }
    end
  end

  # Individual health checks

  defp check_database do
    # Check if database is accessible
    case FnNotifications.Infrastructure.Repositories.NotificationRepository.health_check() do
      :ok -> :ok
      error -> {:error, "Database error: #{inspect(error)}"}
    end
  rescue
    error -> {:error, "Database connection failed: #{inspect(error)}"}
  end

  defp check_kafka do
    # Check if Kafka is accessible (simplified check)
    # In a real implementation, you'd ping Kafka brokers
    :ok
  rescue
    error -> {:error, "Kafka check failed: #{inspect(error)}"}
  end

  defp check_redis do
    # Check Redis connectivity (if using Redis for caching)
    case Application.get_env(:fn_notifications, :cache_adapter) do
      FnNotifications.Infrastructure.Cache.RedisAdapter ->
        # Would implement actual Redis ping here
        :ok
      _ ->
        :ok  # Not using Redis
    end
  rescue
    error -> {:error, "Redis check failed: #{inspect(error)}"}
  end

  defp check_twilio do
    # Check Twilio service availability
    case FnNotifications.Infrastructure.Clients.TwilioClient.health_check() do
      :ok -> :ok
      error -> {:error, "Twilio error: #{inspect(error)}"}
    end
  rescue
    error -> {:error, "Twilio check failed: #{inspect(error)}"}
  end

  defp check_email_service do
    # Check email service (Swoosh) health
    case FnNotifications.Infrastructure.Adapters.EmailAdapter.health_check() do
      :ok -> :ok
      error -> {:error, "Email service error: #{inspect(error)}"}
    end
  rescue
    error -> {:error, "Email service check failed: #{inspect(error)}"}
  end

  defp check_circuit_breakers do
    # Check circuit breaker states
    try do
      twilio_state = GenServer.call(FnNotifications.Domain.Services.CircuitBreakerService, :get_state)

      case twilio_state do
        %{state: :open} -> {:error, "Circuit breakers are open"}
        %{state: :half_open} -> :ok  # Half-open is acceptable
        %{state: :closed} -> :ok
        _ -> {:error, "Unknown circuit breaker state"}
      end
    catch
      _, _ -> {:error, "Circuit breaker service unavailable"}
    end
  end

  defp check_bulkhead_pools do
    # Check bulkhead pool health
    try do
      stats = FnNotifications.Domain.Services.BulkheadService.get_pool_stats()

      # Check if any pools are over 90% utilized
      overloaded = Enum.filter(stats, fn {_pool, %{utilization: util}} -> util > 0.9 end)

      case overloaded do
        [] -> :ok
        pools -> {:error, "Overloaded pools: #{inspect(Enum.map(pools, &elem(&1, 0)))}"}
      end
    catch
      _, _ -> {:error, "Bulkhead service unavailable"}
    end
  end

  defp calculate_overall_status(checks) do
    statuses = Enum.map(checks, fn {_name, %{status: status}} -> status end)

    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      true -> :degraded
    end
  end

  defp get_system_info do
    %{
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000),
      memory_usage: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      node_name: Node.self()
    }
  end
end