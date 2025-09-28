defmodule FnNotifications.Application.Commands.SendNotificationCommand do
  @moduledoc """
  Command for sending a notification through the system.
  """

  alias FnNotifications.Domain.ValueObjects.NotificationChannel

  @type t :: %__MODULE__{
          user_id: String.t(),
          channel: NotificationChannel.t(),
          title: String.t(),
          body: String.t(),
          metadata: map(),
          scheduled_at: DateTime.t() | nil,
          max_retries: non_neg_integer()
        }

  @enforce_keys [:user_id, :channel, :title, :body]
  defstruct [
    :user_id,
    :channel,
    :title,
    :body,
    :metadata,
    :scheduled_at,
    max_retries: 3
  ]

  @doc """
  Creates a new SendNotificationCommand.
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    with {:ok, user_id} <- validate_user_id(attrs[:user_id]),
         {:ok, channel} <- validate_channel(attrs[:channel]),
         {:ok, title} <- validate_title(attrs[:title]),
         {:ok, body} <- validate_body(attrs[:body]) do
      command = %__MODULE__{
        user_id: user_id,
        channel: channel,
        title: title,
        body: body,
        metadata: attrs[:metadata] || %{},
        scheduled_at: attrs[:scheduled_at],
        max_retries: attrs[:max_retries] || 3
      }

      {:ok, command}
    end
  end

  defp validate_user_id(user_id) when is_binary(user_id) and byte_size(user_id) > 0, do: {:ok, user_id}
  defp validate_user_id(_), do: {:error, "user_id is required"}

  defp validate_channel(channel) when channel in [:email, :sms, :whatsapp], do: {:ok, channel}
  defp validate_channel(_), do: {:error, "invalid channel"}

  defp validate_title(title) when is_binary(title) and byte_size(title) > 0, do: {:ok, title}
  defp validate_title(_), do: {:error, "title is required"}

  defp validate_body(body) when is_binary(body) and byte_size(body) > 0, do: {:ok, body}
  defp validate_body(_), do: {:error, "body is required"}
end
