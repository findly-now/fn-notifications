defmodule FnNotifications.Domain.Services.NotificationRoutingService do
  @moduledoc """
  Simple routing logic for notification delivery.
  """

  alias FnNotifications.Domain.Entities.{Notification, UserPreferences}

  @type routing_decision :: %{
          should_deliver: boolean(),
          delay_until: DateTime.t() | nil,
          reason: String.t() | nil
        }

  @doc """
  Determines if notification should be delivered now using simple validation.
  """
  @spec route_notification(Notification.t(), UserPreferences.t()) :: routing_decision()
  def route_notification(%Notification{channel: channel}, preferences) do
    cond do
      not user_can_receive_on_channel?(preferences, channel) ->
        %{should_deliver: false, delay_until: nil, reason: "Channel disabled for user"}

      not UserPreferences.notifications_allowed_now?(preferences, channel) ->
        %{should_deliver: false, delay_until: nil, reason: "Quiet hours active"}

      true ->
        %{should_deliver: true, delay_until: nil, reason: nil}
    end
  end

  # Simple helper functions
  defp user_can_receive_on_channel?(preferences, channel) do
    UserPreferences.channel_enabled?(preferences, channel)
  end

end
