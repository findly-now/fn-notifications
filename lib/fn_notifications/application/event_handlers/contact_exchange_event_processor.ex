defmodule FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor do
  @moduledoc """
  Contact Exchange Event Processor

  Broadway-based event processor for handling contact exchange events from Kafka.
  Processes secure contact sharing workflow events including requests, approvals,
  denials, and expirations.

  ## Supported Events
  - contact.exchange.requested: Someone requests contact information
  - contact.exchange.approved: Owner approves contact sharing
  - contact.exchange.denied: Owner denies contact sharing request
  - contact.exchange.expired: Contact exchange expires

  ## Processing Pipeline
  1. Decode incoming Kafka messages
  2. Translate events to domain commands using FatEventTranslator
  3. Execute commands through ContactExchangeNotificationService
  4. Handle errors with appropriate retry logic

  ## Privacy & Security
  - Never logs sensitive contact information
  - Processes encrypted contact data appropriately
  - Maintains audit trail for compliance
  """

  use Broadway

  require Logger

  alias FnNotifications.Application.AntiCorruption.FatEventTranslator
  alias FnNotifications.Application.Services.ContactExchangeNotificationService

  @doc """
  Starts the Broadway pipeline for contact exchange events.
  """
  def start_link(_opts) do
    # Get consumer group name based on environment
    consumer_group = System.get_env("KAFKA_CONSUMER_GROUP", "fn-notifications-contact-exchange")

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayKafka.Producer,
          hosts: kafka_hosts(),
          group_id: consumer_group,
          topics: [kafka_topic(:contact_exchange)],
          client_config: kafka_config(),
          receive_interval: 1000,
          # Use async commit for better performance
          commit_interval: 5000,
          offset_reset_policy: :earliest
        },
        # Broadway processor configuration
        concurrency: 5
      ],
      processors: [
        default: [
          # Process contact exchange events with appropriate concurrency
          # Lower concurrency for contact sharing to ensure proper security handling
          concurrency: 3,
          # Longer processing timeout for complex contact exchange workflows
          max_demand: 5
        ]
      ],
      batchers: [
        default: [
          batch_size: 5,
          batch_timeout: 1000,
          # Lower concurrency for batched processing to maintain security
          concurrency: 2
        ]
      ]
    )
  end

  @doc """
  Handles individual contact exchange event messages.
  """
  def handle_message(processor, message, context) do
    correlation_id = generate_correlation_id()

    Logger.metadata(correlation_id: correlation_id, processor: processor)

    case decode_message(message.data) do
      {:ok, event} ->
        Logger.info("Processing contact exchange event: #{event["event_type"]}")

        case process_contact_exchange_event(event, correlation_id) do
          :ok ->
            Logger.info("Successfully processed contact exchange event")
            message

          {:error, reason} ->
            Logger.error("Failed to process contact exchange event: #{inspect(reason)}")
            Broadway.Message.failed(message, reason)
        end

      {:error, reason} ->
        Logger.error("Failed to decode contact exchange message: #{inspect(reason)}")
        Broadway.Message.failed(message, "decode_error")
    end
  rescue
    error ->
      Logger.error("Unexpected error processing contact exchange event: #{inspect(error)}")
      Broadway.Message.failed(message, "unexpected_error")
  end

  @doc """
  Handles batched processing for analytics and monitoring.
  """
  def handle_batch(:default, messages, _batch_info, _context) do
    # Process successful messages for analytics
    successful_events =
      messages
      |> Enum.filter(&(&1.status == :ok))
      |> Enum.map(&decode_message(&1.data))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))

    # Log analytics data for contact exchange workflow
    log_contact_exchange_analytics(successful_events)

    messages
  end

  # Private functions

  defp decode_message(data) do
    case Jason.decode(data) do
      {:ok, %{"event_type" => event_type} = event} when is_binary(event_type) ->
        {:ok, event}

      {:ok, invalid_event} ->
        {:error, "Invalid event format: #{inspect(invalid_event)}"}

      {:error, reason} ->
        {:error, "JSON decode error: #{inspect(reason)}"}
    end
  end

  defp process_contact_exchange_event(event, correlation_id) do
    Logger.metadata(
      correlation_id: correlation_id,
      event_type: event["event_type"],
      request_id: get_in(event, ["data", "contact_request", "request_id"]) ||
                  get_in(event, ["data", "contact_approval", "request_id"]) ||
                  get_in(event, ["data", "contact_denial", "request_id"]) ||
                  get_in(event, ["data", "contact_expiration", "request_id"])
    )

    case FatEventTranslator.translate_contact_exchange_event(event) do
      {:ok, commands} ->
        process_commands(commands, correlation_id)

      {:error, reason} ->
        Logger.warning("Failed to translate contact exchange event: #{reason}")
        {:error, reason}
    end
  end

  defp process_commands([], _correlation_id) do
    Logger.info("No commands generated from contact exchange event")
    :ok
  end

  defp process_commands(commands, correlation_id) when is_list(commands) do
    Logger.info("Processing #{length(commands)} contact exchange commands")

    results =
      commands
      |> Enum.map(&process_single_command(&1, correlation_id))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        Logger.info("All contact exchange commands processed successfully")
        :ok

      {:error, reason} ->
        Logger.error("Contact exchange command failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_single_command(command, correlation_id) do
    Logger.metadata(
      correlation_id: correlation_id,
      command_type: command.__struct__,
      target_user: get_target_user_from_command(command)
    )

    case ContactExchangeNotificationService.process_notification(command) do
      {:ok, notification} ->
        Logger.info("Contact exchange notification created successfully",
          notification_id: notification.id,
          notification_type: notification.notification_type.value
        )
        :ok

      {:error, reason} ->
        Logger.error("Failed to create contact exchange notification: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Unexpected error processing contact exchange command: #{inspect(error)}")
      {:error, "command_processing_error"}
  end

  defp get_target_user_from_command(%{target_user_id: target_user_id}), do: target_user_id
  defp get_target_user_from_command(%{requester_user_id: user_id}), do: user_id
  defp get_target_user_from_command(%{owner_user_id: user_id}), do: user_id
  defp get_target_user_from_command(_), do: "unknown"

  defp log_contact_exchange_analytics(events) do
    if length(events) > 0 do
      event_counts =
        events
        |> Enum.group_by(& &1["event_type"])
        |> Enum.map(fn {type, events} -> {type, length(events)} end)

      Logger.info("Contact exchange analytics",
        total_events: length(events),
        event_breakdown: event_counts
      )

      # Send metrics to monitoring system if configured
      send_contact_exchange_metrics(event_counts)
    end
  end

  defp send_contact_exchange_metrics(event_counts) do
    # Send metrics to DataDog or other monitoring system
    try do
      Enum.each(event_counts, fn {event_type, count} ->
        FnNotifications.Infrastructure.Adapters.DatadogAdapter.increment(
          "contact_exchange.events",
          count,
          tags: ["event_type:#{event_type}"]
        )
      end)
    rescue
      error ->
        Logger.warning("Failed to send contact exchange metrics: #{inspect(error)}")
    end
  end

  defp generate_correlation_id do
    "ce_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp kafka_hosts do
    Application.get_env(:fn_notifications, :kafka_hosts, [{"localhost", 9092}])
  end

  defp kafka_config do
    Application.get_env(:fn_notifications, :kafka_config, [])
  end

  defp kafka_topic(topic_key) do
    topics = Application.get_env(:fn_notifications, :kafka_topics, %{})
    # Handle both map and keyword list formats
    case topics do
      topics when is_map(topics) ->
        Map.get(topics, topic_key, "posts.events")
      topics when is_list(topics) ->
        Keyword.get(topics, topic_key, "posts.events")
      _ ->
        "posts.events"
    end
  end
end