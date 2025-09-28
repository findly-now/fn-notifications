defmodule FnNotifications.Application.DTO.NotificationDTO do
  @moduledoc """
  Data Transfer Object for notifications, used for API responses and cross-boundary data transfer.
  """

  alias FnNotifications.Domain.Entities.Notification

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          channel: String.t(),
          status: String.t(),
          title: String.t(),
          body: String.t(),
          metadata: map(),
          scheduled_at: String.t() | nil,
          sent_at: String.t() | nil,
          delivered_at: String.t() | nil,
          failed_at: String.t() | nil,
          failure_reason: String.t() | nil,
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer(),
          inserted_at: String.t(),
          updated_at: String.t()
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :user_id,
    :channel,
    :status,
    :title,
    :body,
    :metadata,
    :scheduled_at,
    :sent_at,
    :delivered_at,
    :failed_at,
    :failure_reason,
    :retry_count,
    :max_retries,
    :inserted_at,
    :updated_at
  ]

  @doc """
  Creates a DTO from a notification entity.
  """
  @spec from_entity(Notification.t()) :: t()
  def from_entity(%Notification{} = notification) do
    %__MODULE__{
      id: notification.id,
      user_id: notification.user_id,
      channel: to_string(notification.channel),
      status: to_string(notification.status),
      title: notification.title,
      body: notification.body,
      metadata: notification.metadata,
      scheduled_at: format_datetime(notification.scheduled_at),
      sent_at: format_datetime(notification.sent_at),
      delivered_at: format_datetime(notification.delivered_at),
      failed_at: format_datetime(notification.failed_at),
      failure_reason: notification.failure_reason,
      retry_count: notification.retry_count,
      max_retries: notification.max_retries,
      inserted_at: format_datetime(notification.inserted_at),
      updated_at: format_datetime(notification.updated_at)
    }
  end

  @doc """
  Creates a list of DTOs from a list of notification entities.
  """
  @spec from_entities([Notification.t()]) :: [t()]
  def from_entities(notifications) when is_list(notifications) do
    Enum.map(notifications, &from_entity/1)
  end

  @doc """
  Returns a summary DTO with only essential fields (for listing views).
  """
  @spec summary(Notification.t()) :: map()
  def summary(%Notification{} = notification) do
    %{
      id: notification.id,
      channel: to_string(notification.channel),
      status: to_string(notification.status),
      title: notification.title,
      scheduled_at: format_datetime(notification.scheduled_at),
      sent_at: format_datetime(notification.sent_at),
      delivered_at: format_datetime(notification.delivered_at),
      inserted_at: format_datetime(notification.inserted_at)
    }
  end

  @doc """
  Returns delivery status information.
  """
  @spec delivery_status(Notification.t()) :: map()
  def delivery_status(%Notification{} = notification) do
    %{
      id: notification.id,
      status: to_string(notification.status),
      sent_at: format_datetime(notification.sent_at),
      delivered_at: format_datetime(notification.delivered_at),
      failed_at: format_datetime(notification.failed_at),
      failure_reason: notification.failure_reason,
      retry_count: notification.retry_count,
      max_retries: notification.max_retries,
      can_retry: notification.retry_count < notification.max_retries
    }
  end

  # Private helper functions
  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end
end
