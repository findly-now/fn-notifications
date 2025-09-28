defmodule FnNotifications.Infrastructure.Adapters.WhatsAppAdapter do
  @moduledoc """
  WhatsApp message delivery adapter.
  """

  alias FnNotifications.Infrastructure.Clients.TwilioClient
  alias FnNotifications.Domain.Entities.Notification
  alias FnNotifications.Domain.Services.BulkheadService

  @behaviour FnNotifications.Infrastructure.Adapters.DeliveryAdapterBehavior

  @impl true
  def delivery_method, do: :whatsapp

  @impl true
  def can_deliver?(%Notification{channel: :whatsapp, metadata: metadata}) do
    phone_number = Map.get(metadata, "phone_number")
    not is_nil(phone_number) and String.starts_with?(phone_number, "whatsapp:")
  end
  def can_deliver?(_), do: false

  @impl true
  def deliver_notification(%Notification{} = notification) do
    case deliver(notification) do
      :success -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec deliver(Notification.t()) :: :success | {:error, String.t()}
  def deliver(%Notification{} = notification) do
    case BulkheadService.execute(:whatsapp_delivery, fn ->
      deliver_whatsapp_internal(notification)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_whatsapp_delivery(%Notification{metadata: metadata, body: body}) do
    phone_number = Map.get(metadata, "phone_number")

    with :ok <- TwilioClient.validate_whatsapp_number(phone_number),
         :ok <- TwilioClient.validate_whatsapp_body(body) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_whatsapp_params(%Notification{metadata: metadata} = notification) do
    phone_number = Map.get(metadata, "phone_number")

    params = %{
      to: phone_number,
      body: notification.body
    }

    {:ok, params}
  end

  defp deliver_whatsapp_internal(%Notification{} = notification) do
    with :ok <- validate_whatsapp_delivery(notification),
         {:ok, whatsapp_params} <- build_whatsapp_params(notification),
         {:ok, _response} <- TwilioClient.send_whatsapp_message(whatsapp_params) do
      :success
    else
      {:error, reason} -> {:error, reason}
    end
  end
end