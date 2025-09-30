defmodule FnNotifications.Application.EventHandlers.UsersEventProcessor do
  @moduledoc """
  Broadway pipeline for processing user events and generating notifications.
  """

  use Broadway

  alias FnNotifications.Application.Services.NotificationService
  alias FnNotifications.Application.AntiCorruption.FatEventTranslator

  require Logger


  def start_link(_opts) do
    # Get consumer group name based on environment
    consumer_group = System.get_env("KAFKA_CONSUMER_GROUP", "fn_notifications_users")

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayKafka.Producer,
          hosts: kafka_hosts(),
          group_id: consumer_group,
          topics: [kafka_topic(:users_events)],
          offset_reset_policy: :earliest,
          begin_offset: :reset,
          client_config: kafka_config()
        }
      ],
      processors: [
        default: [
          concurrency: 5
        ]
      ],
      batchers: [
        default: [
          batch_size: 20,
          batch_timeout: 2000
        ]
      ]
    )
  end

  @impl true
  @spec handle_message(atom(), Broadway.Message.t(), map()) :: Broadway.Message.t()
  def handle_message(_, message, _) do
    case Jason.decode(message.data) do
      {:ok, event_data} ->
        case FatEventTranslator.translate_user_event(event_data) do
          {:ok, notification_commands} ->
            %{message | data: notification_commands}

          {:error, reason} ->
            Logger.warning("Failed to translate user event: #{reason}")
            Broadway.Message.failed(message, reason)
        end

      {:error, _} ->
        Logger.error("Failed to parse user event JSON: #{inspect(message.data)}")
        Broadway.Message.failed(message, "invalid_json")
    end
  rescue
    exception ->
      Logger.error("Error processing user event: #{inspect(exception)}")
      Broadway.Message.failed(message, "processing_error")
  end

  @impl true
  @spec handle_batch(atom(), [Broadway.Message.t()], map(), map()) :: [Broadway.Message.t()]
  def handle_batch(_, messages, _, _) do
    notification_commands =
      messages
      |> Enum.flat_map(fn message -> message.data end)
      |> Enum.filter(& &1)

    case send_notifications_batch(notification_commands) do
      :ok ->
        Logger.info("Successfully processed batch of #{length(messages)} user events")
        messages

      {:error, _failed_commands} ->
        Logger.error("Failed to process some user notifications in batch")
        Enum.map(messages, &Broadway.Message.failed(&1, "Batch processing failed"))
    end
  end

  # Private functions

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
      Logger.warning("#{failed_count}/#{length(commands)} user notifications failed")
      {:error, "Some notifications failed"}
    end
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