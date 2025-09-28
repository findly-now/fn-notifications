defmodule FnNotifications.Application.EventHandlers.PostsEventProcessor do
  @moduledoc """
  Broadway pipeline for processing posts events and generating notifications.
  """

  use Broadway

  alias FnNotifications.Application.Services.NotificationService
  alias FnNotifications.Application.AntiCorruption.EventTranslator

  # For generating correlation IDs
  alias UUID

  require Logger


  def start_link(_opts) do
    # Get consumer group name based on environment
    consumer_group = System.get_env("KAFKA_CONSUMER_GROUP", "fn_notifications_posts")

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayKafka.Producer,
          hosts: kafka_hosts(),
          group_id: consumer_group,
          topics: ["posts.events"],
          offset_reset_policy: :earliest,
          begin_offset: :reset,
          config: kafka_config()
        }
      ],
      processors: [
        default: [
          concurrency: 10
        ]
      ],
      batchers: [
        default: [
          batch_size: 50,
          batch_timeout: 1000
        ]
      ]
    )
  end

  @impl Broadway
  @spec handle_message(atom(), Broadway.Message.t(), map()) :: Broadway.Message.t()
  def handle_message(:default, message, _context) do
    correlation_id = extract_correlation_id(message.metadata)
    Logger.metadata(correlation_id: correlation_id)

    case decode_message(message) do
      {:ok, event} ->
        case EventTranslator.translate_post_event(event) do
          {:ok, notification_commands} ->
            %{message | data: notification_commands}

          {:error, reason} ->
            Logger.warning("Failed to translate post event: #{reason}")
            Broadway.Message.failed(message, reason)
        end

      {:error, reason} ->
        Logger.error("Failed to decode message: #{reason}")
        Broadway.Message.failed(message, reason)
    end
  end

  @impl Broadway
  @spec handle_batch(atom(), [Broadway.Message.t()], map(), map()) :: [Broadway.Message.t()]
  def handle_batch(_batcher, messages, _batch_info, _context) do
    notification_commands =
      messages
      |> Enum.flat_map(fn message -> message.data end)
      |> Enum.filter(& &1)

    case send_notifications_batch(notification_commands) do
      :ok ->
        Logger.info("Successfully processed batch of #{length(messages)} messages")
        messages

      {:error, _failed_commands} ->
        Logger.error("Failed to process some notifications in batch")
        # For simplicity, mark all as failed - could be more sophisticated
        Enum.map(messages, &Broadway.Message.failed(&1, "Batch processing failed"))
    end
  end

  # Private functions

  defp decode_message(message) do
    try do
      event = Jason.decode!(message.data)
      {:ok, event}
    rescue
      Jason.DecodeError -> {:error, "Invalid JSON"}
    end
  end

  defp send_notifications_batch(commands) do
    results =
      commands
      |> Enum.map(fn command ->
        case NotificationService.send_notification(command) do
          {:ok, _notification_id} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

    failed_count = Enum.count(results, &match?({:error, _}, &1))

    if failed_count == 0 do
      :ok
    else
      Logger.warning("#{failed_count}/#{length(commands)} notifications failed")
      {:error, "Some notifications failed"}
    end
  end

  defp kafka_hosts do
    Application.get_env(:fn_notifications, :kafka_hosts, [{"localhost", 9092}])
  end

  defp kafka_config do
    Application.get_env(:fn_notifications, :kafka_config, [])
  end

  defp extract_correlation_id(metadata) do
    case Map.get(metadata, :headers, []) do
      headers when is_list(headers) ->
        Enum.find_value(headers, fn
          {"correlation_id", correlation_id} -> correlation_id
          {"x-correlation-id", correlation_id} -> correlation_id
          _ -> nil
        end) || UUID.uuid4()

      _ ->
        UUID.uuid4()
    end
  end
end