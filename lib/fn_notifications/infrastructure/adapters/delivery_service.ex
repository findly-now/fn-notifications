defmodule FnNotifications.Infrastructure.Adapters.DeliveryService do
  @moduledoc """
  Coordinates delivery across multiple notification channels.
  Routes notifications to appropriate adapters based on channel type.
  """

  alias FnNotifications.Domain.Entities.{Notification, UserPreferences}

  alias FnNotifications.Infrastructure.Adapters.{
    DatadogAdapter,
    EmailAdapter,
    SmsAdapter
  }

  require Logger

  @adapters %{
    email: EmailAdapter,
    sms: SmsAdapter,
    # WhatsApp uses SMS adapter via Twilio
    whatsapp: SmsAdapter
  }

  @doc """
  Delivers a notification using the appropriate channel adapter.
  """
  @spec deliver(Notification.t()) :: :ok | {:error, String.t()}
  def deliver(%Notification{channel: channel} = notification) do
    case get_adapter(channel) do
      {:ok, adapter} ->
        if adapter.can_deliver?(notification) do
          result = adapter.deliver_notification(notification)
          status = if result == :ok, do: :sent, else: :failed
          DatadogAdapter.track_notification_sent(to_string(channel), status)
          result
        else
          DatadogAdapter.track_notification_sent(to_string(channel), :failed)
          {:error, "Adapter #{adapter} cannot deliver notification #{notification.id}"}
        end

      {:error, reason} ->
        DatadogAdapter.track_notification_sent(to_string(channel), :failed)
        {:error, reason}
    end
  end

  @doc """
  Delivers a notification using user preferences for contact information.
  """
  @spec deliver(Notification.t(), UserPreferences.t()) :: :ok | {:error, String.t()}
  def deliver(%Notification{channel: channel} = notification, user_preferences) do
    case get_adapter(channel) do
      {:ok, adapter} ->
        # Use the new deliver_notification/2 function that accepts user preferences
        result = adapter.deliver_notification(notification, user_preferences)
        status = if result == :ok, do: :sent, else: :failed
        DatadogAdapter.track_notification_sent(to_string(channel), status)
        result

      {:error, reason} ->
        DatadogAdapter.track_notification_sent(to_string(channel), :failed)
        {:error, reason}
    end
  end

  @doc """
  Delivers a notification with fallback to alternative channels.
  """
  @spec deliver_with_fallback(Notification.t(), [atom()]) :: :ok | {:error, String.t()}
  def deliver_with_fallback(%Notification{} = notification, fallback_channels \\ []) do
    channels_to_try = [notification.channel | fallback_channels]

    case attempt_delivery_on_channels(notification, channels_to_try) do
      :ok ->
        :ok

      {:error, errors} ->
        all_errors = Enum.join(errors, "; ")

        Logger.error("All delivery attempts failed",
          notification_id: notification.id,
          channels: channels_to_try,
          errors: all_errors
        )

        {:error, "All delivery channels failed: #{all_errors}"}
    end
  end

  @doc """
  Checks if a notification can be delivered through its specified channel.
  """
  @spec can_deliver?(Notification.t()) :: boolean()
  def can_deliver?(%Notification{channel: channel} = notification) do
    case get_adapter(channel) do
      {:ok, adapter} -> adapter.can_deliver?(notification)
      {:error, _} -> false
    end
  end

  @doc """
  Gets available delivery channels.
  """
  @spec available_channels() :: [atom()]
  def available_channels do
    Map.keys(@adapters)
  end

  @doc """
  Validates if a channel is supported.
  """
  @spec supported_channel?(atom()) :: boolean()
  def supported_channel?(channel) do
    Map.has_key?(@adapters, channel)
  end

  @doc """
  Gets delivery statistics for monitoring.
  """
  @spec get_delivery_stats() :: map()
  def get_delivery_stats do
    # This would typically aggregate from metrics or monitoring systems
    %{
      total_deliveries: get_total_deliveries(),
      success_rate: get_success_rate(),
      channel_stats: get_channel_stats(),
      last_updated: DateTime.utc_now()
    }
  end

  @doc """
  Tests connectivity to all delivery channels.
  """
  @spec health_check() :: %{atom() => :ok | {:error, String.t()}}
  def health_check do
    @adapters
    |> Enum.map(fn {channel, adapter} ->
      status =
        case perform_health_check(adapter) do
          :ok -> :ok
          error -> error
        end

      {channel, status}
    end)
    |> Enum.into(%{})
  end

  # Private helper functions
  defp get_adapter(channel) do
    case Map.get(@adapters, channel) do
      nil -> {:error, "Unsupported channel: #{channel}"}
      adapter -> {:ok, adapter}
    end
  end

  defp attempt_delivery_on_channels(notification, channels) do
    results =
      Enum.map(channels, fn channel ->
        adapted_notification = %{notification | channel: channel}

        case deliver(adapted_notification) do
          :ok ->
            Logger.info("Delivery successful on channel #{channel}",
              notification_id: notification.id
            )

            :ok

          {:error, reason} ->
            Logger.warning("Delivery failed on channel #{channel}: #{reason}",
              notification_id: notification.id
            )

            {:error, "#{channel}: #{reason}"}
        end
      end)

    successful_deliveries = Enum.filter(results, fn result -> result == :ok end)

    if length(successful_deliveries) > 0 do
      :ok
    else
      error_messages =
        results
        |> Enum.filter(fn result -> match?({:error, _}, result) end)
        |> Enum.map(fn {:error, msg} -> msg end)

      {:error, error_messages}
    end
  end

  defp perform_health_check(adapter) do
    # Basic health check - verify adapter module exists and responds
    try do
      if function_exported?(adapter, :delivery_method, 0) do
        _method = adapter.delivery_method()
        :ok
      else
        {:error, "Adapter does not implement delivery_method/0"}
      end
    rescue
      error ->
        {:error, "Health check failed: #{inspect(error)}"}
    end
  end

  defp get_total_deliveries do
    # Mock implementation - in real app, this would query metrics/database
    42_000
  end

  defp get_success_rate do
    # Mock implementation - in real app, this would calculate from metrics
    0.987
  end

  defp get_channel_stats do
    # Mock implementation - in real app, this would aggregate by channel
    %{
      email: %{deliveries: 15_000, success_rate: 0.995},
      sms: %{deliveries: 5_000, success_rate: 0.978},
      whatsapp: %{deliveries: 3_500, success_rate: 0.985}
    }
  end
end
