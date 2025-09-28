defmodule FnNotifications.Infrastructure.Adapters.SmsAdapter do
  @moduledoc """
  SMS and WhatsApp notification adapter using Tesla HTTP client for Twilio API integration.
  Handles both SMS and WhatsApp message delivery through Twilio's unified API.
  """

  alias FnNotifications.Domain.Entities.{Notification, UserPreferences}
  alias FnNotifications.Infrastructure.Clients.TwilioClient
  alias FnNotifications.Domain.Services.BulkheadService

  require Logger

  @behaviour FnNotifications.Infrastructure.Adapters.DeliveryAdapterBehavior

  @doc """
  Delivers a notification via SMS or WhatsApp through Twilio API.
  """
  @impl true
  def deliver_notification(%Notification{channel: channel} = notification) when channel in [:sms, :whatsapp] do
    operation_type = if channel == :sms, do: :sms_delivery, else: :whatsapp_delivery

    case BulkheadService.execute(operation_type, fn ->
      deliver_message_internal(notification)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def deliver_notification(%Notification{channel: channel}) do
    {:error, "SmsAdapter cannot handle channel: #{channel}"}
  end

  @doc """
  Delivers a notification via SMS or WhatsApp with user preferences providing contact info.
  """
  @spec deliver_notification(Notification.t(), UserPreferences.t()) :: :ok | {:error, String.t()}
  def deliver_notification(%Notification{channel: channel} = notification, user_preferences) when channel in [:sms, :whatsapp] do
    operation_type = if channel == :sms, do: :sms_delivery, else: :whatsapp_delivery

    case BulkheadService.execute(operation_type, fn ->
      deliver_message_internal(notification, user_preferences)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def deliver_notification(%Notification{channel: channel}, _user_preferences) do
    {:error, "SmsAdapter cannot handle channel: #{channel}"}
  end

  @doc """
  Validates if the notification can be delivered via SMS or WhatsApp.
  """
  @impl true
  def can_deliver?(%Notification{channel: channel} = notification) when channel in [:sms, :whatsapp] do
    case get_phone_number(notification.user_id) do
      {:ok, _phone} -> true
    end
  end

  def can_deliver?(%Notification{}), do: false

  @doc """
  Gets delivery method identifier.
  """
  @impl true
  def delivery_method, do: :sms_whatsapp

  # Private helper functions
  defp get_phone_number(user_id) do
    # This would typically fetch from a user service or database
    case Application.get_env(:fn_notifications, :test_mode, false) do
      true ->
        # Test phone number
        {:ok, "+1234567890"}

      false ->
        # In production, this would call a user service
        fetch_user_phone_number(user_id)
    end
  end

  defp validate_phone_number(nil) do
    {:error, "User phone number is not configured"}
  end

  defp validate_phone_number(phone) when is_binary(phone) do
    if String.starts_with?(phone, "+") and String.length(phone) > 5 do
      {:ok, phone}
    else
      {:error, "Invalid phone number format - must be in E.164 format"}
    end
  end

  defp validate_phone_number(_) do
    {:error, "Phone number must be a string"}
  end

  defp fetch_user_phone_number(user_id) do
    # Fetch from user preferences repository
    case FnNotifications.Infrastructure.Repositories.UserPreferencesRepository.get_by_user_id(user_id) do
      {:ok, %{phone: phone}} when is_binary(phone) -> {:ok, phone}
      {:ok, %{phone: nil}} -> {:error, "User phone not configured in preferences"}
      {:error, :not_found} -> {:error, "User preferences not found"}
      {:error, reason} -> {:error, "Failed to fetch user preferences: #{inspect(reason)}"}
    end
  end

  defp build_message_content(%Notification{channel: :sms} = notification) do
    # SMS has strict length limits (160 characters for single SMS)
    max_length = 160
    build_content_with_limit(notification, max_length)
  end

  defp build_message_content(%Notification{channel: :whatsapp} = notification) do
    # WhatsApp has higher character limits (1600 characters)
    max_length = 1600
    build_content_with_limit(notification, max_length)
  end

  defp build_content_with_limit(%Notification{} = notification, max_length) do
    # Build content based on notification type
    content =
      case get_message_template(notification) do
        {:ok, template} -> render_message_template(template, notification)
      end

    # Truncate if too long
    final_content =
      if String.length(content) > max_length do
        String.slice(content, 0, max_length - 3) <> "..."
      else
        content
      end

    {:ok, final_content}
  end

  defp get_message_template(%Notification{metadata: %{"event_type" => event_type}}) do
    case event_type do
      "post.created" -> {:ok, "message_post_created"}
      "post.matched" -> {:ok, "message_post_matched"}
      "post.claimed" -> {:ok, "message_post_claimed"}
      "post.resolved" -> {:ok, "message_post_resolved"}
      _ -> {:ok, "message_generic"}
    end
  end

  defp get_message_template(%Notification{}), do: {:ok, "message_generic"}

  defp render_message_template("message_post_created", notification) do
    "Lost & Found: #{notification.body}"
  end

  defp render_message_template("message_post_matched", notification) do
    "Match Found! #{notification.body}"
  end

  defp render_message_template("message_post_claimed", notification) do
    "Item Claim: #{notification.body}"
  end

  defp render_message_template("message_post_resolved", notification) do
    "Item Resolved! #{notification.body}"
  end

  defp render_message_template("message_generic", notification) do
    "#{notification.title}: #{notification.body}"
  end

  defp render_message_template(_template, notification) do
    fallback_message_content(notification)
  end

  defp fallback_message_content(%Notification{title: title, body: body}) do
    "#{title}: #{body}"
  end

  defp send_message(phone_number, content, :sms) do
    case Application.get_env(:fn_notifications, :test_mode, false) do
      true ->
        Logger.info("""
        📱 SMS TEST MODE - Would send SMS:
        To: #{phone_number}
        From: #{twilio_phone_number()}
        Body: #{content}
        """)

        {:ok, %{"sid" => "test_sms_#{:rand.uniform(999_999)}"}}

      false ->
        TwilioClient.send_sms(%{
          to: phone_number,
          body: content,
          from: twilio_phone_number()
        })
    end
  end

  defp send_message(phone_number, content, :whatsapp) do
    case Application.get_env(:fn_notifications, :test_mode, false) do
      true ->
        Logger.info("""
        💬 WHATSAPP TEST MODE - Would send WhatsApp message:
        To: whatsapp:#{phone_number}
        From: #{twilio_whatsapp_number()}
        Body: #{content}
        """)

        {:ok, %{"sid" => "test_whatsapp_#{:rand.uniform(999_999)}"}}

      false ->
        TwilioClient.send_whatsapp_message(%{
          to: "whatsapp:#{phone_number}",
          body: content,
          from: twilio_whatsapp_number()
        })
    end
  end

  defp twilio_phone_number do
    Application.get_env(:fn_notifications, :twilio_phone_number, "+15551234567")
  end

  defp twilio_whatsapp_number do
    Application.get_env(:fn_notifications, :twilio_whatsapp_number, "whatsapp:+14155238886")
  end

  defp deliver_message_internal(%Notification{channel: channel} = notification) do
    with {:ok, phone_number} <- get_phone_number(notification.user_id),
         {:ok, content} <- build_message_content(notification),
         {:ok, _result} <- send_message(phone_number, content, channel) do
      channel_name = String.upcase(to_string(channel))
      Logger.info("#{channel_name} delivered successfully", notification_id: notification.id)
      :ok
    else
      {:error, reason} ->
        channel_name = String.upcase(to_string(channel))

        Logger.error("#{channel_name} delivery failed: #{inspect(reason)}",
          notification_id: notification.id
        )

        {:error, format_error(reason)}
    end
  end

  defp deliver_message_internal(%Notification{channel: channel} = notification, %UserPreferences{phone: phone}) do
    with {:ok, phone_number} <- validate_phone_number(phone),
         {:ok, content} <- build_message_content(notification),
         {:ok, _result} <- send_message(phone_number, content, channel) do
      channel_name = String.upcase(to_string(channel))
      Logger.info("#{channel_name} delivered successfully", notification_id: notification.id)
      :ok
    else
      {:error, reason} ->
        channel_name = String.upcase(to_string(channel))

        Logger.error("#{channel_name} delivery failed: #{inspect(reason)}",
          notification_id: notification.id
        )

        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: "SMS delivery error: #{inspect(reason)}"
end
