defmodule FnNotifications.Domain.ValueObjects.NotificationChannel do
  @moduledoc """
  Notification delivery channel types.
  """

  @type t :: :email | :sms | :whatsapp

  @valid_channels [:email, :sms, :whatsapp]

  def all, do: @valid_channels
  def valid?(channel), do: channel in @valid_channels
end
