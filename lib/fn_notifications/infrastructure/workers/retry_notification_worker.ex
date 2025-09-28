defmodule FnNotifications.Infrastructure.Workers.RetryNotificationWorker do
  @moduledoc """
  Oban worker for retry processing of failed notifications.
  """

  use Oban.Worker, queue: :retries, max_attempts: 3

  alias FnNotifications.Application.Services.NotificationService
  alias FnNotifications.Infrastructure.Adapters.DatadogAdapter

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id, "attempt" => attempt}}) do
    Logger.info("Retrying notification #{notification_id}, attempt #{attempt}")

    case NotificationService.process_delivery_attempt(notification_id) do
      {:ok, _notification} ->
        DatadogAdapter.track_notification_sent("retry", :success)
        Logger.info("Successfully retried notification #{notification_id}")
        :ok

      {:error, reason} ->
        DatadogAdapter.track_notification_sent("retry", :failed)
        Logger.error("Failed to retry notification #{notification_id}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Schedules a notification for retry with exponential backoff.
  """
  @spec schedule_retry(String.t(), non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_retry(notification_id, attempt \\ 1) do
    delay_seconds = calculate_delay(attempt)

    %{notification_id: notification_id, attempt: attempt}
    |> __MODULE__.new(schedule_in: delay_seconds)
    |> Oban.insert()
  end

  # Exponential backoff: 30s, 90s, 270s
  defp calculate_delay(1), do: 30
  defp calculate_delay(2), do: 90
  defp calculate_delay(3), do: 270
  # Cap at 270s
  defp calculate_delay(_), do: 270
end
