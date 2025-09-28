defmodule FnNotifications.Domain.Services.NotificationDeduplicationService do
  @moduledoc """
  Simple hash-based deduplication service for notifications.
  """

  alias FnNotifications.Domain.Entities.Notification

  @type deduplication_key :: String.t()
  @type deduplication_window :: pos_integer()

  @doc """
  Generates a simple deduplication key based on notification content.
  """
  @spec generate_deduplication_key(map()) :: deduplication_key()
  def generate_deduplication_key(%{user_id: user_id, channel: channel, title: title, body: body}) do
    content = "#{user_id}:#{channel}:#{title}:#{body}"

    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Gets deduplication window in seconds based on channel.
  """
  @spec get_deduplication_window(Notification.t()) :: deduplication_window()
  def get_deduplication_window(%Notification{channel: channel}) do
    case channel do
      :email -> 600      # 10 minutes
      :sms -> 900        # 15 minutes
      :whatsapp -> 300   # 5 minutes
      _ -> 600           # Default 10 minutes
    end
  end
end
