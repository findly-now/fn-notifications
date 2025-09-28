defmodule FnNotifications.Infrastructure.Adapters.DeliveryAdapterBehavior do
  @moduledoc """
  Behavior contract for notification delivery adapters.
  Each delivery channel (email, SMS, WhatsApp) must implement this behavior.
  """

  alias FnNotifications.Domain.Entities.Notification

  @doc """
  Delivers a notification using the specific channel implementation.
  Returns :ok on success, or {:error, reason} on failure.
  """
  @callback deliver_notification(Notification.t()) :: :ok | {:error, String.t()}

  @doc """
  Checks if the adapter can deliver the given notification.
  Should validate channel compatibility and recipient availability.
  """
  @callback can_deliver?(Notification.t()) :: boolean()

  @doc """
  Returns the delivery method identifier for this adapter.
  """
  @callback delivery_method() :: atom()
end
