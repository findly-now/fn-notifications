defmodule FnNotifications.Infrastructure.Adapters.DatadogAdapter do
  @moduledoc """
  Statix-based Datadog metrics adapter for notification system observability.
  """
  use Statix, runtime_config: true

  @doc """
  Track notification delivery metrics.
  """
  @spec track_notification_sent(String.t(), atom()) :: :ok
  def track_notification_sent(channel, status) when channel in ["email", "sms", "whatsapp"] and is_atom(status) do
    safe_increment("notification.sent", tags: ["channel:#{channel}", "status:#{status}"])
  end

  @doc """
  Track event processing performance.
  """
  @spec track_event_processed(String.t(), non_neg_integer()) :: :ok
  def track_event_processed(event_type, duration_ms) do
    safe_increment("event.processed", tags: ["type:#{event_type}"])
    safe_histogram("event.duration", duration_ms, tags: ["type:#{event_type}"])
  end

  @doc """
  Track health check results.
  """
  @spec track_health_check(String.t(), String.t()) :: :ok
  def track_health_check(component, status) do
    safe_gauge("health.status", if(status == "healthy", do: 1, else: 0), tags: ["component:#{component}"])
  end

  @doc """
  Track notification creation metrics.
  """
  @spec track_notification_created(String.t()) :: :ok
  def track_notification_created(channel) do
    safe_increment("notification.created", tags: ["channel:#{channel}"])
  end

  @doc """
  Track notification failures with detailed error categorization.
  """
  @spec track_notification_failed(String.t(), String.t()) :: :ok
  def track_notification_failed(channel, error_category) do
    safe_increment("notification.failed", tags: ["channel:#{channel}", "error:#{error_category}"])
  end

  @doc """
  Track duplicate notifications detected and suppressed.
  """
  @spec track_duplicate_suppressed(String.t()) :: :ok
  def track_duplicate_suppressed(channel) do
    safe_increment("notification.duplicate_suppressed", tags: ["channel:#{channel}"])
  end

  @doc """
  Track retry attempts for failed notifications.
  """
  @spec track_retry_scheduled(String.t(), non_neg_integer()) :: :ok
  def track_retry_scheduled(_notification_id, attempt) do
    safe_increment("notification.retry_scheduled", tags: ["attempt:#{attempt}"])
    safe_histogram("notification.retry_delay", calculate_retry_delay(attempt), tags: ["attempt:#{attempt}"])
  end

  @doc """
  Track user preference updates.
  """
  @spec track_preference_updated(String.t(), String.t()) :: :ok
  def track_preference_updated(_user_id, preference_type) do
    safe_increment("user.preference_updated", tags: ["type:#{preference_type}"])
  end

  @doc """
  Track event bus operations.
  """
  @spec track_event_published(String.t(), non_neg_integer()) :: :ok
  def track_event_published(event_type, batch_size) do
    safe_increment("event_bus.published", tags: ["type:#{event_type}"])
    safe_histogram("event_bus.batch_size", batch_size, tags: ["type:#{event_type}"])
  end

  # Private safe wrapper functions to handle missing Statix configuration
  defp safe_increment(metric, opts) do
    try do
      increment(metric, opts)
    rescue
      ArgumentError -> :ok  # Statix not configured, skip metrics
    end
  end

  defp safe_gauge(metric, value, opts) do
    try do
      gauge(metric, value, opts)
    rescue
      ArgumentError -> :ok  # Statix not configured, skip metrics
    end
  end

  defp safe_histogram(metric, value, opts) do
    try do
      histogram(metric, value, opts)
    rescue
      ArgumentError -> :ok  # Statix not configured, skip metrics
    end
  end

  # Private helper to calculate retry delay for metrics
  defp calculate_retry_delay(attempt) do
    base_delay = 30
    round(base_delay * :math.pow(3, attempt))
  end
end
