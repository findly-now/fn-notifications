defmodule FnNotificationsWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and load balancing.
  """

  use FnNotificationsWeb, :controller
  alias FnNotifications.Infrastructure.Adapters.DatadogAdapter

  @doc """
  Comprehensive health check with dependency validation.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    checks = %{
      database: check_database(),
      kafka: check_kafka(),
      twilio: check_twilio(),
      memory: check_memory()
    }

    overall_status = determine_overall_status(checks)

    health_data = %{
      status: overall_status,
      service: "fn-notifications",
      version: get_app_version(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: checks
    }

    # Track health metrics
    Enum.each(checks, fn {component, status} ->
      DatadogAdapter.track_health_check(to_string(component), status)
    end)

    status_code = if overall_status == "healthy", do: :ok, else: :service_unavailable

    conn
    |> put_status(status_code)
    |> json(health_data)
  end

  # Private helper functions
  defp get_app_version do
    case Application.spec(:fn_notifications, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp check_database do
    try do
      case FnNotifications.Repo.query("SELECT 1", []) do
        {:ok, _} -> "healthy"
        {:error, _} -> "unhealthy"
      end
    rescue
      _ -> "unhealthy"
    end
  end

  defp check_kafka do
    try do
      # Check if Broadway supervisor is running first
      case Process.whereis(FnNotifications.Application.PostsEventProcessor) do
        nil -> "starting"  # Broadway not started yet, not critical during startup
        _pid ->
          # Broadway is running, check if producers are configured
          try do
            broadway_pids = Broadway.producer_names(FnNotifications.Application.PostsEventProcessor)
            if length(broadway_pids) > 0, do: "healthy", else: "unhealthy"
          rescue
            # Handle case where Broadway topology config is not available yet
            _ -> "starting"
          end
      end
    rescue
      _ -> "unhealthy"
    end
  end

  defp check_twilio do
    try do
      twilio_sid = Application.get_env(:fn_notifications, :twilio_account_sid)
      if is_binary(twilio_sid) and String.length(twilio_sid) > 0, do: "configured", else: "unconfigured"
    rescue
      _ -> "error"
    end
  end

  defp check_memory do
    memory_usage = :erlang.memory(:total)
    # 1GB threshold
    max_memory = 1_000_000_000

    if memory_usage < max_memory do
      "healthy"
    else
      "warning"
    end
  end

  defp determine_overall_status(checks) do
    critical_checks = [:database, :kafka]

    critical_unhealthy =
      Enum.any?(critical_checks, fn check ->
        status = Map.get(checks, check)
        # Only consider "unhealthy" as critical, not "starting"
        status == "unhealthy"
      end)

    # If any critical service is unhealthy, mark as unhealthy
    # "starting" services are considered acceptable during startup
    if critical_unhealthy, do: "unhealthy", else: "healthy"
  end

end
