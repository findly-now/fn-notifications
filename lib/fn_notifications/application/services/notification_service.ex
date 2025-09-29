defmodule FnNotifications.Application.Services.NotificationService do
  @moduledoc """
  Application service for managing notification operations and orchestrating
  between domain aggregates and infrastructure services.
  """

  alias FnNotifications.Domain.Aggregates.NotificationAggregate
  alias FnNotifications.Domain.Entities.UserPreferences
  alias FnNotifications.Domain.Services.{NotificationRoutingService, NotificationDeduplicationService}
  alias FnNotifications.Application.Commands.SendNotificationCommand
  alias FnNotifications.Application.DTO.NotificationDTO
  alias FnNotifications.Application.Services.UserPreferencesService

  # For generating correlation IDs for domain events
  alias UUID

  # Metrics tracking
  alias FnNotifications.Infrastructure.Adapters.DatadogAdapter

  # These would be implemented as repository behaviors in infrastructure layer
  @notification_repository Application.compile_env(:fn_notifications, :notification_repository)
  @preferences_repository Application.compile_env(:fn_notifications, :preferences_repository)
  @delivery_service Application.compile_env(:fn_notifications, :delivery_service)

  @type send_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Sends a notification through the system with full business rule validation.
  """
  @spec send_notification(SendNotificationCommand.t()) :: send_result()
  def send_notification(%SendNotificationCommand{} = command) do
    with {:ok, notification_aggregate} <- create_notification(command),
         {:ok, user_preferences} <- get_user_preferences(command.user_id),
         {:ok, routing_decision} <- route_notification(notification_aggregate, user_preferences),
         {:ok, final_aggregate} <- process_delivery(notification_aggregate, routing_decision) do
      # Persist the notification and emit events
      persist_notification_and_emit_events(final_aggregate)
    end
  end

  @doc """
  Processes a notification delivery attempt.
  """
  @spec process_delivery_attempt(String.t()) :: {:ok, NotificationDTO.t()} | {:error, String.t()}
  def process_delivery_attempt(notification_id) do
    with {:ok, aggregate} <- load_notification_aggregate(notification_id),
         :ok <- NotificationAggregate.validate_for_processing(aggregate),
         notification <- NotificationAggregate.notification(aggregate),
         {:ok, user_preferences} <- get_user_preferences(notification.user_id),
         {:ok, sent_aggregate} <- NotificationAggregate.send(aggregate),
         {:ok, delivery_result} <- attempt_delivery(sent_aggregate, user_preferences) do
      case delivery_result do
        :success ->
          {:ok, delivered_aggregate} = NotificationAggregate.mark_delivered(sent_aggregate)
          persist_and_return(delivered_aggregate)

        {:error, reason} ->
          {:ok, failed_aggregate} = NotificationAggregate.mark_failed(sent_aggregate, reason)

          if NotificationAggregate.notification(failed_aggregate).retry_count <
               NotificationAggregate.notification(failed_aggregate).max_retries do
            # Schedule retry
            schedule_retry(failed_aggregate)
          end

          persist_and_return(failed_aggregate)
      end
    end
  end

  @doc """
  Gets notification status and details.
  """
  @spec get_notification(String.t()) :: {:ok, NotificationDTO.t()} | {:error, String.t()}
  def get_notification(notification_id) do
    case @notification_repository.get_by_id(notification_id) do
      {:ok, notification} -> {:ok, NotificationDTO.from_entity(notification)}
      {:error, :not_found} -> {:error, "Notification not found"}
      error -> error
    end
  end

  @doc """
  Gets notifications for a user with filtering options.
  """
  @spec get_user_notifications(String.t(), map()) :: {:ok, [NotificationDTO.t()]} | {:error, String.t()}
  def get_user_notifications(user_id, filters \\ %{}) do
    case @notification_repository.get_by_user_id(user_id, filters) do
      {:ok, notifications} ->
        dtos = Enum.map(notifications, &NotificationDTO.from_entity/1)
        {:ok, dtos}

      error ->
        error
    end
  end

  # Private helper functions
  @spec create_notification(SendNotificationCommand.t()) :: {:ok, NotificationAggregate.t()} | {:error, String.t()}
  defp create_notification(%SendNotificationCommand{} = command) do
    deduplication_key =
      NotificationDeduplicationService.generate_deduplication_key(%{
        user_id: command.user_id,
        channel: command.channel,
        title: command.title,
        body: command.body
      })

    DatadogAdapter.track_notification_created(Atom.to_string(command.channel))

    NotificationAggregate.create(%{
      user_id: command.user_id,
      channel: command.channel,
      title: command.title,
      body: command.body,
      metadata: Map.put(command.metadata, :deduplication_key, deduplication_key),
      scheduled_at: command.scheduled_at,
      max_retries: command.max_retries
    })
  end

  @spec get_user_preferences(String.t()) :: {:ok, UserPreferences.t()} | {:error, term()}
  defp get_user_preferences(user_id) do
    case @preferences_repository.get_by_user_id(user_id) do
      {:ok, preferences} ->
        {:ok, preferences}

      {:error, :not_found} ->
        UserPreferencesService.create_default_preferences(user_id)

      error ->
        error
    end
  end

  @spec route_notification(NotificationAggregate.t(), UserPreferences.t()) :: {:ok, map()}
  defp route_notification(notification_aggregate, user_preferences) do
    notification = NotificationAggregate.notification(notification_aggregate)
    routing_decision = NotificationRoutingService.route_notification(notification, user_preferences)
    {:ok, routing_decision}
  end

  @spec process_delivery(NotificationAggregate.t(), map()) :: {:ok, NotificationAggregate.t()} | {:error, String.t()}
  defp process_delivery(notification_aggregate, routing_decision) do
    if routing_decision.should_deliver do
      # Send immediately
      {:ok, notification_aggregate}
    else
      # Schedule for later or handle rejection
      case routing_decision.delay_until do
        nil ->
          # Reject delivery
          NotificationAggregate.cancel(notification_aggregate, routing_decision.reason || "Delivery rejected")

        delay_until ->
          # Update scheduled_at and keep pending
          notification = NotificationAggregate.notification(notification_aggregate)
          updated_notification = %{notification | scheduled_at: delay_until}
          {:ok, %{notification_aggregate | notification: updated_notification}}
      end
    end
  end


  @spec attempt_delivery(NotificationAggregate.t(), UserPreferences.t()) :: :success | {:error, String.t()}
  defp attempt_delivery(notification_aggregate, user_preferences) do
    notification = NotificationAggregate.notification(notification_aggregate)
    case @delivery_service.deliver(notification, user_preferences) do
      :ok -> :success
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_notification_and_emit_events(NotificationAggregate.t()) :: {:ok, String.t()} | {:error, term()}
  defp persist_notification_and_emit_events(notification_aggregate) do
    notification = NotificationAggregate.notification(notification_aggregate)

    case @notification_repository.save(notification) do
      {:ok, saved_notification} ->
        {:ok, saved_notification.id}

      error ->
        error
    end
  end

  defp persist_and_return(notification_aggregate) do
    notification = NotificationAggregate.notification(notification_aggregate)

    case @notification_repository.save(notification) do
      {:ok, saved_notification} ->
        {:ok, NotificationDTO.from_entity(saved_notification)}

      error ->
        error
    end
  end

  @spec load_notification_aggregate(String.t()) :: {:ok, NotificationAggregate.t()} | {:error, term()}
  defp load_notification_aggregate(notification_id) do
    case @notification_repository.get_by_id(notification_id) do
      {:ok, notification} -> {:ok, NotificationAggregate.load(notification)}
      error -> error
    end
  end

  @spec schedule_retry(NotificationAggregate.t()) :: {:ok, term()} | {:error, String.t()}
  defp schedule_retry(notification_aggregate) do
    notification = NotificationAggregate.notification(notification_aggregate)
    retry_count = notification.retry_count + 1

    case FnNotifications.Infrastructure.Workers.RetryNotificationWorker.schedule_retry(
           notification.id,
           retry_count
         ) do
      {:ok, job} ->
        # Track retry scheduling metrics
        DatadogAdapter.track_retry_scheduled(notification.id, retry_count)
        require Logger
        Logger.info("Scheduled retry for notification #{notification.id}, attempt #{retry_count}")
        {:ok, job}

      {:error, reason} ->
        # Track retry scheduling failures
        DatadogAdapter.track_notification_failed(
          Atom.to_string(notification.channel),
          "retry_scheduling_failed"
        )

        require Logger
        Logger.error("Failed to schedule retry for notification #{notification.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end


end
