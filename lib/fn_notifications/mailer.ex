defmodule FnNotifications.Mailer do
  @moduledoc """
  Swoosh mailer configuration for email delivery.
  """

  use Swoosh.Mailer, otp_app: :fn_notifications
end
