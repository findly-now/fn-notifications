defmodule FnNotifications.Application.Services.ContactExchangeNotificationService do
  @moduledoc """
  Contact Exchange Notification Service

  Application service responsible for processing contact exchange notifications
  in the secure contact sharing workflow. This service orchestrates the creation
  and delivery of notifications for contact exchange requests, approvals, denials,
  and expirations.

  ## Responsibilities
  - Create contact exchange notifications from commands
  - Apply business rules for notification delivery
  - Coordinate with delivery adapters for multi-channel notifications
  - Handle privacy and security requirements for contact sharing
  - Manage notification state transitions

  ## Privacy & Security Features
  - Encrypts contact information before storage
  - Implements time-limited contact sharing
  - Never logs sensitive contact data
  - Validates user permissions for contact access
  """

  require Logger

  alias FnNotifications.Application.Commands.SendContactExchangeNotificationCommand
  alias FnNotifications.Domain.Entities.ContactExchangeNotification
  alias FnNotifications.Domain.Repositories.ContactExchangeNotificationRepositoryBehavior
  alias FnNotifications.Domain.Services.ContactEncryptionService
  alias FnNotifications.Infrastructure.Adapters.DeliveryService

  @behaviour ContactExchangeNotificationServiceBehavior

  @doc """
  Processes a contact exchange notification command.

  Creates the appropriate notification entity, persists it, and initiates
  the delivery process according to the user's preferences and the
  notification urgency.
  """
  @spec process_notification(SendContactExchangeNotificationCommand.t()) ::
          {:ok, ContactExchangeNotification.t()} | {:error, term()}
  def process_notification(%SendContactExchangeNotificationCommand{} = command) do
    Logger.info("Processing contact exchange notification",
      request_id: command.request_id,
      notification_type: command.notification_type,
      target_user: SendContactExchangeNotificationCommand.target_user_id(command)
    )

    with {:ok, notification} <- create_notification_from_command(command),
         {:ok, persisted_notification} <- persist_notification(notification),
         :ok <- initiate_delivery(persisted_notification, command) do
      Logger.info("Contact exchange notification processed successfully",
        notification_id: persisted_notification.id,
        request_id: command.request_id
      )

      {:ok, persisted_notification}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process contact exchange notification",
          request_id: command.request_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Finds contact exchange notifications by request ID.
  """
  @spec find_by_request_id(String.t()) ::
          {:ok, ContactExchangeNotification.t()} | {:error, :not_found}
  def find_by_request_id(request_id) when is_binary(request_id) do
    contact_exchange_repo().find_by_request_id(request_id)
  end

  @doc """
  Finds all contact exchange notifications for a user (as requester).
  """
  @spec find_user_requests(String.t()) ::
          {:ok, [ContactExchangeNotification.t()]} | {:error, term()}
  def find_user_requests(user_id) when is_binary(user_id) do
    contact_exchange_repo().find_by_requester_user_id(user_id)
  end

  @doc """
  Finds all contact exchange notifications for a user (as owner).
  """
  @spec find_user_received_requests(String.t()) ::
          {:ok, [ContactExchangeNotification.t()]} | {:error, term()}
  def find_user_received_requests(user_id) when is_binary(user_id) do
    contact_exchange_repo().find_by_owner_user_id(user_id)
  end

  @doc """
  Marks a contact exchange notification as sent.
  """
  @spec mark_notification_sent(String.t()) ::
          {:ok, ContactExchangeNotification.t()} | {:error, term()}
  def mark_notification_sent(notification_id) when is_binary(notification_id) do
    contact_exchange_repo().mark_as_sent(notification_id)
  end

  @doc """
  Cleanup expired contact exchange notifications for privacy compliance.
  """
  @spec cleanup_expired_notifications() :: {:ok, integer()} | {:error, term()}
  def cleanup_expired_notifications do
    Logger.info("Starting cleanup of expired contact exchange notifications")

    case contact_exchange_repo().delete_expired_notifications() do
      {:ok, count} ->
        Logger.info("Cleaned up #{count} expired contact exchange notifications")
        {:ok, count}

      {:error, reason} = error ->
        Logger.error("Failed to cleanup expired notifications: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp create_notification_from_command(%SendContactExchangeNotificationCommand{
         notification_type: :request_received
       } = command) do
    ContactExchangeNotification.create_request_notification(%{
      request_id: command.request_id,
      requester_user_id: command.requester_user_id,
      owner_user_id: command.owner_user_id,
      related_post_id: command.related_post_id,
      metadata: build_notification_metadata(command)
    })
  end

  defp create_notification_from_command(%SendContactExchangeNotificationCommand{
         notification_type: :approval_granted
       } = command) do
    ContactExchangeNotification.create_approval_notification(%{
      request_id: command.request_id,
      requester_user_id: command.requester_user_id,
      owner_user_id: command.owner_user_id,
      related_post_id: command.related_post_id,
      contact_info: encrypt_contact_info(command.contact_info),
      expires_at: command.expires_at,
      metadata: build_notification_metadata(command)
    })
  end

  defp create_notification_from_command(%SendContactExchangeNotificationCommand{
         notification_type: :denial_sent
       } = command) do
    ContactExchangeNotification.create_denial_notification(%{
      request_id: command.request_id,
      requester_user_id: command.requester_user_id,
      owner_user_id: command.owner_user_id,
      related_post_id: command.related_post_id,
      metadata: build_notification_metadata(command)
    })
  end

  defp create_notification_from_command(%SendContactExchangeNotificationCommand{
         notification_type: :expiration_notice
       } = command) do
    ContactExchangeNotification.create_expiration_notification(%{
      request_id: command.request_id,
      requester_user_id: command.requester_user_id,
      owner_user_id: command.owner_user_id,
      related_post_id: command.related_post_id,
      metadata: build_notification_metadata(command)
    })
  end

  defp build_notification_metadata(command) do
    Map.merge(command.metadata, %{
      "post_context" => command.post_context,
      "user_preferences" => SendContactExchangeNotificationCommand.target_user_preferences(command),
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp encrypt_contact_info(contact_info) when map_size(contact_info) == 0, do: %{}

  defp encrypt_contact_info(contact_info) do
    # Use proper encryption service for contact information
    case ContactEncryptionService.encrypt_contact_info(contact_info, get_contact_expiration()) do
      {:ok, encrypted_contact} ->
        # Store the encrypted contact info with audit logging
        ContactEncryptionService.audit_contact_access(
          "system",  # System user for encryption
          "unknown", # Request ID not available at this point
          "contact_exchange",
          :encrypt
        )

        encrypted_contact

      {:error, reason} ->
        Logger.error("Failed to encrypt contact information: #{inspect(reason)}")
        # Return empty map if encryption fails for security
        %{}
    end
  end

  defp get_contact_expiration do
    # Contact information expires 24 hours after approval
    DateTime.utc_now() |> DateTime.add(24, :hour)
  end

  defp persist_notification(notification) do
    case contact_exchange_repo().create(notification) do
      {:ok, persisted} ->
        Logger.debug("Contact exchange notification persisted",
          notification_id: persisted.id,
          type: persisted.notification_type.value
        )

        {:ok, persisted}

      {:error, reason} = error ->
        Logger.error("Failed to persist contact exchange notification: #{inspect(reason)}")
        error
    end
  end

  defp initiate_delivery(notification, command) do
    target_user_id = ContactExchangeNotification.target_user_id(notification)
    user_preferences = SendContactExchangeNotificationCommand.target_user_preferences(command)

    delivery_params = %{
      notification_id: notification.id,
      user_id: target_user_id,
      user_preferences: user_preferences,
      notification_type: :contact_exchange,
      urgent: SendContactExchangeNotificationCommand.urgent?(command),
      content: build_notification_content(notification, command),
      metadata: %{
        "contact_exchange_type" => notification.notification_type.value,
        "request_id" => notification.request_id,
        "includes_contact_info" => ContactExchangeNotification.target_user_id(notification) != notification.owner_user_id &&
                                   SendContactExchangeNotificationCommand.includes_contact_info?(command)
      }
    }

    case DeliveryService.schedule_delivery(delivery_params) do
      :ok ->
        Logger.info("Contact exchange notification delivery scheduled",
          notification_id: notification.id,
          user_id: target_user_id
        )
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to schedule contact exchange notification delivery",
          notification_id: notification.id,
          reason: inspect(reason)
        )
        error
    end
  end

  defp build_notification_content(notification, command) do
    %{
      title: build_notification_title(notification, command),
      body: build_notification_body(notification, command),
      action_url: build_action_url(notification, command),
      template_data: build_template_data(notification, command)
    }
  end

  defp build_notification_title(notification, command) do
    post_title = get_in(command.metadata, ["post_title"]) || "item"

    case notification.notification_type.value do
      :request_received ->
        "Someone wants to contact you about '#{post_title}'"

      :approval_granted ->
        "Contact information shared for '#{post_title}'"

      :denial_sent ->
        "Contact request declined for '#{post_title}'"

      :expiration_notice ->
        "Contact exchange expired for '#{post_title}'"
    end
  end

  defp build_notification_body(notification, command) do
    post_title = get_in(command.metadata, ["post_title"]) || "your item"
    requester_name = get_in(command.metadata, ["requester_name"]) || "Someone"
    owner_name = get_in(command.metadata, ["owner_name"]) || "The item owner"

    case notification.notification_type.value do
      :request_received ->
        message = get_in(command.metadata, ["request_message"])
        base_message = "#{requester_name} would like to contact you about #{post_title}."
        if message, do: "#{base_message} Message: \"#{message}\"", else: base_message

      :approval_granted ->
        "#{owner_name} has approved your contact request for #{post_title}. " <>
        "You can now coordinate to recover your item. The contact information will expire " <>
        "in 24 hours for privacy protection."

      :denial_sent ->
        reason = get_in(command.metadata, ["denial_reason"]) || "owner preference"
        "Your contact request for #{post_title} was declined. Reason: #{reason}. " <>
        "You may try contacting through the platform messaging system instead."

      :expiration_notice ->
        "The contact exchange for #{post_title} has expired. " <>
        "For privacy protection, shared contact information is no longer accessible."
    end
  end

  defp build_action_url(notification, command) do
    base_url = Application.get_env(:fn_notifications, :web_base_url, "http://localhost:4000")
    post_id = notification.related_post_id

    case notification.notification_type.value do
      :request_received ->
        "#{base_url}/posts/#{post_id}/contact-requests"

      :approval_granted ->
        "#{base_url}/posts/#{post_id}/contact"

      :denial_sent ->
        "#{base_url}/posts/#{post_id}"

      :expiration_notice ->
        "#{base_url}/posts/#{post_id}"
    end
  end

  defp build_template_data(notification, command) do
    Map.merge(command.metadata, %{
      "notification_type" => notification.notification_type.value,
      "request_id" => notification.request_id,
      "post_id" => notification.related_post_id,
      "expires_at" => notification.expires_at && DateTime.to_iso8601(notification.expires_at)
    })
  end

  defp contact_exchange_repo do
    Application.get_env(:fn_notifications, :contact_exchange_repository,
      FnNotifications.Infrastructure.Repositories.ContactExchangeNotificationRepository
    )
  end
end

defmodule FnNotifications.Application.Services.ContactExchangeNotificationServiceBehavior do
  @moduledoc """
  Behavior for Contact Exchange Notification Service
  """

  alias FnNotifications.Application.Commands.SendContactExchangeNotificationCommand
  alias FnNotifications.Domain.Entities.ContactExchangeNotification

  @callback process_notification(SendContactExchangeNotificationCommand.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, term()}

  @callback find_by_request_id(String.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, :not_found}

  @callback find_user_requests(String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @callback find_user_received_requests(String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @callback mark_notification_sent(String.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, term()}

  @callback cleanup_expired_notifications() :: {:ok, integer()} | {:error, term()}
end