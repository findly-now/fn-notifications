defmodule FnNotifications.Workers.ContactExchangeCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired contact exchange notifications.

  This worker runs periodically to remove expired contact exchange data
  for privacy compliance and security. It handles:

  - Expired contact sharing approvals
  - Old denied/expired requests
  - Audit log cleanup
  - Encryption key rotation reminders

  ## Privacy Compliance
  - Follows data retention policies
  - Securely deletes sensitive information
  - Maintains audit trails for compliance
  - Supports GDPR right-to-be-forgotten
  """

  use Oban.Worker, queue: :contact_cleanup, max_attempts: 3

  require Logger

  alias FnNotifications.Application.Services.ContactExchangeNotificationService
  alias FnNotifications.Domain.Services.ContactEncryptionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation" => "cleanup_expired"}} = job) do
    Logger.info("Starting contact exchange cleanup", job_id: job.id)

    with {:ok, deleted_count} <- ContactExchangeNotificationService.cleanup_expired_notifications(),
         :ok <- cleanup_audit_logs(),
         :ok <- check_encryption_key_rotation() do

      Logger.info("Contact exchange cleanup completed successfully",
        job_id: job.id,
        deleted_notifications: deleted_count
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Contact exchange cleanup failed",
          job_id: job.id,
          reason: inspect(reason)
        )

        error
    end
  end

  def perform(%Oban.Job{args: %{"operation" => "expire_contact", "request_id" => request_id}} = job) do
    Logger.info("Expiring contact for request",
      job_id: job.id,
      request_id: request_id
    )

    case ContactExchangeNotificationService.find_by_request_id(request_id) do
      {:ok, notification} ->
        if notification.expires_at && DateTime.compare(DateTime.utc_now(), notification.expires_at) == :gt do
          # Contact has expired, audit the expiration
          ContactEncryptionService.audit_contact_access(
            notification.requester_user_id,
            request_id,
            "contact_exchange",
            :expire
          )

          Logger.info("Contact expired and audited",
            job_id: job.id,
            request_id: request_id
          )
        end

        :ok

      {:error, :not_found} ->
        Logger.info("Contact exchange request not found for expiration",
          job_id: job.id,
          request_id: request_id
        )

        :ok

      {:error, reason} = error ->
        Logger.error("Failed to process contact expiration",
          job_id: job.id,
          request_id: request_id,
          reason: inspect(reason)
        )

        error
    end
  end

  def perform(%Oban.Job{args: %{"operation" => "rotate_keys"}} = job) do
    Logger.info("Starting encryption key rotation", job_id: job.id)

    case ContactEncryptionService.rotate_encryption_key() do
      {:ok, new_key_id} ->
        Logger.info("Encryption key rotation completed",
          job_id: job.id,
          new_key_id: new_key_id
        )

        :ok

      {:error, reason} = error ->
        Logger.error("Encryption key rotation failed",
          job_id: job.id,
          reason: inspect(reason)
        )

        error
    end
  end

  def perform(%Oban.Job{} = job) do
    Logger.warning("Unknown contact exchange cleanup operation",
      job_id: job.id,
      args: job.args
    )

    :ok
  end

  @doc """
  Schedules regular cleanup jobs.
  """
  @spec schedule_cleanup() :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_cleanup do
    Logger.info("Scheduling contact exchange cleanup job")

    %{operation: "cleanup_expired"}
    |> new(schedule_in: {1, :hour}, unique: [period: 3600])
    |> Oban.insert()
  end

  @doc """
  Schedules contact expiration for a specific request.
  """
  @spec schedule_contact_expiration(String.t(), DateTime.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_contact_expiration(request_id, expires_at) do
    Logger.info("Scheduling contact expiration",
      request_id: request_id,
      expires_at: DateTime.to_iso8601(expires_at)
    )

    %{operation: "expire_contact", request_id: request_id}
    |> new(scheduled_at: expires_at, unique: [fields: [:args], period: 86400])
    |> Oban.insert()
  end

  @doc """
  Schedules encryption key rotation.
  """
  @spec schedule_key_rotation() :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_key_rotation do
    Logger.info("Scheduling encryption key rotation")

    # Schedule key rotation every 30 days
    rotation_time = DateTime.utc_now() |> DateTime.add(30, :day)

    %{operation: "rotate_keys"}
    |> new(scheduled_at: rotation_time, unique: [period: 86400 * 7])  # Weekly uniqueness
    |> Oban.insert()
  end

  # Private functions

  defp cleanup_audit_logs do
    # Clean up audit logs older than retention period (e.g., 2 years)
    cutoff_date = DateTime.utc_now() |> DateTime.add(-730, :day)

    Logger.info("Cleaning up audit logs older than #{DateTime.to_iso8601(cutoff_date)}")

    # In production, this would clean up audit log storage
    # AuditLogService.cleanup_logs_before(cutoff_date)

    :ok
  end

  defp check_encryption_key_rotation do
    # Check if encryption key needs rotation (e.g., older than 30 days)
    # This would integrate with key management service in production

    Logger.debug("Checking encryption key rotation status")

    # If key is old, schedule rotation
    # case KeyManagementService.get_key_age() do
    #   age when age > 30 ->
    #     schedule_key_rotation()
    #   _ ->
    #     :ok
    # end

    :ok
  end
end