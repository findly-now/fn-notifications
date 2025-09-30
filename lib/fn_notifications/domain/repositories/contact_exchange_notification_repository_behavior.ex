defmodule FnNotifications.Domain.Repositories.ContactExchangeNotificationRepositoryBehavior do
  @moduledoc """
  Repository Behavior for Contact Exchange Notifications

  Defines the contract for persisting and retrieving contact exchange notifications
  in the secure contact sharing workflow. This behavior ensures that the domain
  layer remains independent of infrastructure concerns while providing the
  necessary data access patterns.

  ## Repository Responsibilities

  - Create and update contact exchange notifications
  - Query notifications by various criteria (user, request, post)
  - Handle notification state transitions
  - Support expiration cleanup operations
  - Maintain data consistency with proper error handling
  """

  alias FnNotifications.Domain.Entities.ContactExchangeNotification

  @doc """
  Creates a new contact exchange notification.

  Returns `{:ok, notification}` on success or `{:error, reason}` on failure.
  """
  @callback create(ContactExchangeNotification.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, term()}

  @doc """
  Updates an existing contact exchange notification.

  Returns `{:ok, notification}` on success or `{:error, reason}` on failure.
  """
  @callback update(ContactExchangeNotification.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, term()}

  @doc """
  Finds a contact exchange notification by its ID.

  Returns `{:ok, notification}` if found or `{:error, :not_found}` if not found.
  """
  @callback find_by_id(String.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, :not_found}

  @doc """
  Finds a contact exchange notification by request ID.

  Returns `{:ok, notification}` if found or `{:error, :not_found}` if not found.
  """
  @callback find_by_request_id(String.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, :not_found}

  @doc """
  Finds all contact exchange notifications for a specific requester user.

  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_by_requester_user_id(String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Finds all contact exchange notifications for a specific owner user.

  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_by_owner_user_id(String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Finds all contact exchange notifications related to a specific post.

  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_by_post_id(String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Finds all contact exchange notifications that are pending delivery.

  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_pending_notifications() ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Finds all contact exchange notifications that have expired.

  This is used for cleanup operations to handle expired contact sharing.
  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_expired_notifications() ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Finds all contact exchange notifications by status and type.

  Useful for filtering notifications by workflow state.
  Returns `{:ok, [notification]}` with potentially empty list.
  """
  @callback find_by_status_and_type(String.t(), String.t()) ::
              {:ok, [ContactExchangeNotification.t()]} | {:error, term()}

  @doc """
  Marks a contact exchange notification as sent.

  Updates the notification_sent flag and sent_at timestamp.
  Returns `{:ok, notification}` on success or `{:error, reason}` on failure.
  """
  @callback mark_as_sent(String.t()) ::
              {:ok, ContactExchangeNotification.t()} | {:error, term()}

  @doc """
  Deletes expired contact exchange notifications for cleanup.

  This is used for data retention and privacy compliance.
  Returns `{:ok, count}` where count is the number of deleted records.
  """
  @callback delete_expired_notifications() :: {:ok, integer()} | {:error, term()}

  @doc """
  Counts the total number of contact exchange notifications.

  Useful for monitoring and analytics.
  Returns `{:ok, count}` on success.
  """
  @callback count_all() :: {:ok, integer()} | {:error, term()}

  @doc """
  Counts contact exchange notifications by status.

  Useful for monitoring workflow state distribution.
  Returns `{:ok, count}` on success.
  """
  @callback count_by_status(String.t()) :: {:ok, integer()} | {:error, term()}
end