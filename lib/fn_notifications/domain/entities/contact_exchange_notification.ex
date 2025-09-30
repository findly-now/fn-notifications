defmodule FnNotifications.Domain.Entities.ContactExchangeNotification do
  @moduledoc """
  Contact Exchange Notification Entity

  Domain entity representing a contact exchange notification in the secure contact sharing workflow.
  This entity maintains the business rules for contact exchange notifications including
  privacy constraints, expiration handling, and notification state management.

  ## Business Rules
  - Contact info is never stored in plain text (always encrypted)
  - Requester and owner must be different users
  - Notifications have specific types for each workflow step
  - Exchange status follows a defined state machine
  - Contact sharing has time-based expiration
  """

  alias FnNotifications.Domain.ValueObjects.ContactExchangeStatus
  alias FnNotifications.Domain.ValueObjects.ContactExchangeNotificationType

  defstruct [
    :id,
    :request_id,
    :requester_user_id,
    :owner_user_id,
    :related_post_id,
    :exchange_status,
    :notification_type,
    :contact_info,
    :expires_at,
    :metadata,
    :notification_sent,
    :sent_at,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          request_id: String.t(),
          requester_user_id: String.t(),
          owner_user_id: String.t(),
          related_post_id: String.t(),
          exchange_status: ContactExchangeStatus.t(),
          notification_type: ContactExchangeNotificationType.t(),
          contact_info: map(),
          expires_at: DateTime.t() | nil,
          metadata: map(),
          notification_sent: boolean(),
          sent_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc """
  Creates a new contact exchange notification for a request received event.

  This represents the initial notification sent to the post owner when someone
  requests their contact information.
  """
  @spec create_request_notification(map()) :: {:ok, t()} | {:error, term()}
  def create_request_notification(%{
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        metadata: metadata
      }) do
    with :ok <- validate_different_users(requester_user_id, owner_user_id),
         {:ok, id} <- generate_id(),
         now <- DateTime.utc_now() do
      notification = %__MODULE__{
        id: id,
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: ContactExchangeStatus.pending(),
        notification_type: ContactExchangeNotificationType.request_received(),
        contact_info: %{},
        expires_at: nil,
        metadata: metadata,
        notification_sent: false,
        sent_at: nil,
        inserted_at: now,
        updated_at: now
      }

      {:ok, notification}
    end
  end

  @doc """
  Creates a new contact exchange notification for an approval granted event.

  This represents the notification sent to the requester when the owner
  approves the contact sharing request.
  """
  @spec create_approval_notification(map()) :: {:ok, t()} | {:error, term()}
  def create_approval_notification(%{
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        contact_info: contact_info,
        expires_at: expires_at,
        metadata: metadata
      }) do
    with :ok <- validate_different_users(requester_user_id, owner_user_id),
         :ok <- validate_contact_info(contact_info),
         {:ok, id} <- generate_id(),
         now <- DateTime.utc_now() do
      notification = %__MODULE__{
        id: id,
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: ContactExchangeStatus.approved(),
        notification_type: ContactExchangeNotificationType.approval_granted(),
        contact_info: contact_info,
        expires_at: expires_at,
        metadata: metadata,
        notification_sent: false,
        sent_at: nil,
        inserted_at: now,
        updated_at: now
      }

      {:ok, notification}
    end
  end

  @doc """
  Creates a new contact exchange notification for a denial sent event.

  This represents the notification sent to the requester when the owner
  denies the contact sharing request.
  """
  @spec create_denial_notification(map()) :: {:ok, t()} | {:error, term()}
  def create_denial_notification(%{
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        metadata: metadata
      }) do
    with :ok <- validate_different_users(requester_user_id, owner_user_id),
         {:ok, id} <- generate_id(),
         now <- DateTime.utc_now() do
      notification = %__MODULE__{
        id: id,
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: ContactExchangeStatus.denied(),
        notification_type: ContactExchangeNotificationType.denial_sent(),
        contact_info: %{},
        expires_at: nil,
        metadata: metadata,
        notification_sent: false,
        sent_at: nil,
        inserted_at: now,
        updated_at: now
      }

      {:ok, notification}
    end
  end

  @doc """
  Creates a new contact exchange notification for an expiration notice event.

  This represents the notification sent when a contact exchange expires
  (either the request or the approved contact sharing).
  """
  @spec create_expiration_notification(map()) :: {:ok, t()} | {:error, term()}
  def create_expiration_notification(%{
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        metadata: metadata
      }) do
    with :ok <- validate_different_users(requester_user_id, owner_user_id),
         {:ok, id} <- generate_id(),
         now <- DateTime.utc_now() do
      notification = %__MODULE__{
        id: id,
        request_id: request_id,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: ContactExchangeStatus.expired(),
        notification_type: ContactExchangeNotificationType.expiration_notice(),
        contact_info: %{},
        expires_at: nil,
        metadata: metadata,
        notification_sent: false,
        sent_at: nil,
        inserted_at: now,
        updated_at: now
      }

      {:ok, notification}
    end
  end

  @doc """
  Marks the notification as sent with a timestamp.
  """
  @spec mark_as_sent(t()) :: t()
  def mark_as_sent(%__MODULE__{} = notification) do
    now = DateTime.utc_now()

    %{notification | notification_sent: true, sent_at: now, updated_at: now}
  end

  @doc """
  Checks if the contact exchange has expired based on the expires_at timestamp.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Gets the target user for this notification based on the notification type.

  - request_received: notify the owner
  - approval_granted, denial_sent, expiration_notice: notify the requester
  """
  @spec target_user_id(t()) :: String.t()
  def target_user_id(%__MODULE__{
        notification_type: %ContactExchangeNotificationType{value: :request_received},
        owner_user_id: owner_user_id
      }) do
    owner_user_id
  end

  def target_user_id(%__MODULE__{requester_user_id: requester_user_id}) do
    requester_user_id
  end

  @doc """
  Validates that contact info contains expected encrypted fields for approved exchanges.
  """
  @spec validate_contact_info(map()) :: :ok | {:error, :invalid_contact_info}
  defp validate_contact_info(contact_info) when is_map(contact_info) do
    # Basic validation - ensure we have some contact method
    has_email = Map.has_key?(contact_info, "email") or Map.has_key?(contact_info, :email)
    has_phone = Map.has_key?(contact_info, "phone") or Map.has_key?(contact_info, :phone)

    if has_email or has_phone do
      :ok
    else
      {:error, :invalid_contact_info}
    end
  end

  defp validate_contact_info(_), do: {:error, :invalid_contact_info}

  @doc """
  Validates that requester and owner are different users.
  """
  @spec validate_different_users(String.t(), String.t()) :: :ok | {:error, :same_user}
  defp validate_different_users(user_id, user_id), do: {:error, :same_user}
  defp validate_different_users(_, _), do: :ok

  @doc """
  Generates a unique ID for the notification.
  """
  @spec generate_id() :: {:ok, String.t()}
  defp generate_id do
    {:ok, "ce_notif_" <> UUID.uuid4()}
  end
end