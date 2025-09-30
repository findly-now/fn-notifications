defmodule FnNotifications.Application.Commands.SendContactExchangeNotificationCommand do
  @moduledoc """
  Command to send contact exchange notifications in the secure contact sharing workflow.

  This command encapsulates all the necessary data to process contact exchange notifications
  including request notifications, approval notifications, denial notifications, and
  expiration notices. It includes user preferences extracted from fat events.

  ## Command Types
  - Request received: Notifies post owner of contact exchange request
  - Approval granted: Notifies requester with contact information
  - Denial sent: Notifies requester that request was denied
  - Expiration notice: Notifies users when exchange expires

  ## Privacy and Security
  - Contact information is encrypted when included
  - User preferences are embedded from fat events
  - No cross-domain API calls required for user data
  """

  defstruct [
    :request_id,
    :notification_type,
    :requester_user_id,
    :owner_user_id,
    :related_post_id,
    :exchange_status,
    :contact_info,
    :expires_at,
    :requester_preferences,
    :owner_preferences,
    :post_context,
    :metadata
  ]

  @type notification_type :: :request_received | :approval_granted | :denial_sent | :expiration_notice
  @type exchange_status :: :pending | :approved | :denied | :expired

  @type t :: %__MODULE__{
          request_id: String.t(),
          notification_type: notification_type(),
          requester_user_id: String.t(),
          owner_user_id: String.t(),
          related_post_id: String.t(),
          exchange_status: exchange_status(),
          contact_info: map(),
          expires_at: DateTime.t() | nil,
          requester_preferences: map(),
          owner_preferences: map(),
          post_context: map(),
          metadata: map()
        }

  @doc """
  Creates a new contact exchange notification command.

  ## Parameters
  - `request_id`: Unique identifier for the contact exchange request
  - `notification_type`: Type of notification (:request_received, :approval_granted, etc.)
  - `requester_user_id`: User requesting contact information
  - `owner_user_id`: User who owns the post and contact information
  - `related_post_id`: Post ID related to the exchange
  - `exchange_status`: Current status of the exchange
  - `contact_info`: Encrypted contact information (for approved exchanges)
  - `expires_at`: When the contact access expires
  - `requester_preferences`: User preferences for the requester
  - `owner_preferences`: User preferences for the owner
  - `post_context`: Post details for notification context
  - `metadata`: Additional metadata for the notification
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(%{
        request_id: request_id,
        notification_type: notification_type,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: exchange_status
      } = params)
      when is_binary(request_id) and
             is_binary(requester_user_id) and
             is_binary(owner_user_id) and
             is_binary(related_post_id) and
             notification_type in [:request_received, :approval_granted, :denial_sent, :expiration_notice] and
             exchange_status in [:pending, :approved, :denied, :expired] do

    with :ok <- validate_different_users(requester_user_id, owner_user_id),
         :ok <- validate_notification_type_status_match(notification_type, exchange_status) do
      command = %__MODULE__{
        request_id: request_id,
        notification_type: notification_type,
        requester_user_id: requester_user_id,
        owner_user_id: owner_user_id,
        related_post_id: related_post_id,
        exchange_status: exchange_status,
        contact_info: Map.get(params, :contact_info, %{}),
        expires_at: Map.get(params, :expires_at),
        requester_preferences: Map.get(params, :requester_preferences, %{}),
        owner_preferences: Map.get(params, :owner_preferences, %{}),
        post_context: Map.get(params, :post_context, %{}),
        metadata: Map.get(params, :metadata, %{})
      }

      {:ok, command}
    end
  end

  def new(_params) do
    {:error, :invalid_command_params}
  end

  @doc """
  Gets the target user ID for this notification based on the notification type.
  """
  @spec target_user_id(t()) :: String.t()
  def target_user_id(%__MODULE__{notification_type: :request_received, owner_user_id: owner_user_id}) do
    owner_user_id
  end

  def target_user_id(%__MODULE__{requester_user_id: requester_user_id}) do
    requester_user_id
  end

  @doc """
  Gets the target user preferences for this notification.
  """
  @spec target_user_preferences(t()) :: map()
  def target_user_preferences(%__MODULE__{notification_type: :request_received, owner_preferences: preferences}) do
    preferences
  end

  def target_user_preferences(%__MODULE__{requester_preferences: preferences}) do
    preferences
  end

  @doc """
  Checks if this notification includes contact information.
  """
  @spec includes_contact_info?(t()) :: boolean()
  def includes_contact_info?(%__MODULE__{notification_type: :approval_granted}), do: true
  def includes_contact_info?(%__MODULE__{}), do: false

  @doc """
  Checks if this notification is urgent (requires immediate delivery).
  """
  @spec urgent?(t()) :: boolean()
  def urgent?(%__MODULE__{notification_type: type}) when type in [:approval_granted, :denial_sent], do: true
  def urgent?(%__MODULE__{}), do: false

  @doc """
  Gets the preferred notification channels for the target user.
  """
  @spec preferred_channels(t()) :: [String.t()]
  def preferred_channels(%__MODULE__{} = command) do
    preferences = target_user_preferences(command)

    preferences
    |> Map.get("notification_channels", ["email"])
    |> ensure_list()
  end

  @doc """
  Gets the user's timezone for scheduling notifications.
  """
  @spec user_timezone(t()) :: String.t()
  def user_timezone(%__MODULE__{} = command) do
    preferences = target_user_preferences(command)
    Map.get(preferences, "timezone", "UTC")
  end

  @doc """
  Gets the user's language for notification content.
  """
  @spec user_language(t()) :: String.t()
  def user_language(%__MODULE__{} = command) do
    preferences = target_user_preferences(command)
    Map.get(preferences, "language", "en")
  end

  # Private helper functions

  defp validate_different_users(user_id, user_id), do: {:error, :same_user}
  defp validate_different_users(_, _), do: :ok

  defp validate_notification_type_status_match(:request_received, :pending), do: :ok
  defp validate_notification_type_status_match(:approval_granted, :approved), do: :ok
  defp validate_notification_type_status_match(:denial_sent, :denied), do: :ok
  defp validate_notification_type_status_match(:expiration_notice, :expired), do: :ok
  defp validate_notification_type_status_match(_, _), do: {:error, :mismatched_type_status}

  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list(_), do: ["email"]
end