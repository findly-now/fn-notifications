defmodule FnNotifications.Application.AntiCorruption.EventTranslator do
  @moduledoc """
  Anti-corruption layer for translating external events to domain commands.
  Isolates domain from external schema changes.
  """

  alias FnNotifications.Application.Commands.SendNotificationCommand

  @type external_event :: map()
  @type domain_command :: SendNotificationCommand.t()

  @doc """
  Translates post events from external system to notification commands.
  """
  @spec translate_post_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_post_event(%{"event_type" => event_type, "data" => data} = _event) do
    case event_type do
      "post.created" -> translate_post_created(data)
      "post.matched" -> translate_post_matched(data)
      "post.claimed" -> translate_post_claimed(data)
      "post.resolved" -> translate_post_resolved(data)
      _ -> {:error, "Unknown post event type: #{event_type}"}
    end
  end

  def translate_post_event(_event) do
    {:error, "Invalid post event format"}
  end

  @doc """
  Translates user events from external system to notification commands.
  """
  @spec translate_user_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_user_event(%{"event_type" => event_type, "data" => data} = _event) do
    case event_type do
      "user.registered" -> translate_user_registered(data)
      "organization.staff_added" -> translate_staff_added(data)
      "communication.opt_in" -> translate_communication_opt_in(data)
      _ -> {:error, "Unknown user event type: #{event_type}"}
    end
  end

  def translate_user_event(_event) do
    {:error, "Invalid user event format"}
  end

  # Private translation functions for post events

  defp translate_post_created(%{
         "post_id" => _post_id,
         "reporter_id" => reporter_id,
         "item_type" => _item_type,
         "location" => _location_data
       } = data) do
    variables = build_post_variables(data)

    # Create notifications for nearby users
    commands = [
      build_notification_command(
        reporter_id,
        :email,
        "post.created",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_matched(%{
         "post_id" => _post_id,
         "reporter_id" => reporter_id
       } = data) do
    # Get matcher_id or default to reporter_id if not provided
    matcher_id = Map.get(data, "matcher_id", reporter_id)
    variables = build_post_variables(data)

    commands = [
      build_notification_command(
        reporter_id,
        :email,
        "post.matched",
        variables
      ),
      build_notification_command(
        matcher_id,
        :email,
        "post.matched",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_claimed(%{
         "post_id" => _post_id,
         "reporter_id" => reporter_id,
         "claimer_id" => _claimer_id
       } = data) do
    variables = build_post_variables(data)

    commands = [
      build_notification_command(
        reporter_id,
        :sms,
        "post.claimed",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_resolved(%{
         "post_id" => _post_id,
         "reporter_id" => reporter_id
       } = data) do
    variables = build_post_variables(data)

    commands = [
      build_notification_command(
        reporter_id,
        :email,
        "post.resolved",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  # Private translation functions for user events

  defp translate_user_registered(%{
         "user_id" => user_id
       } = data) do
    # Accept either "name" or "user_name" field
    _user_name = Map.get(data, "name") || Map.get(data, "user_name")
    variables = build_user_variables(data)

    commands = [
      build_notification_command(
        user_id,
        :email,
        "user.registered",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_staff_added(%{
         "user_id" => user_id,
         "organization_name" => _organization_name
       } = data) do
    variables = build_user_variables(data)

    commands = [
      build_notification_command(
        user_id,
        :email,
        "organization.staff_added",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_communication_opt_in(%{
         "user_id" => _user_id
       } = _data) do
    # This event doesn't generate notifications, just updates preferences
    {:ok, []}
  end

  # Helper functions

  defp build_notification_command(user_id, channel, event_type, variables) do
    case SendNotificationCommand.new(%{
           user_id: user_id,
           channel: channel,
           title: get_notification_title(event_type, channel, variables),
           body: get_notification_body(event_type, channel, variables),
           metadata: %{
             event_type: event_type,
             variables: variables
           }
         }) do
      {:ok, command} -> command
      {:error, _reason} -> nil
    end
  end

  defp build_post_variables(data) do
    %{
      "post_id" => Map.get(data, "post_id"),
      "item_type" => Map.get(data, "item_type", "item"),
      "location" => extract_location_string(data),
      "photo_urls" => Map.get(data, "photo_urls", []),
      "thumbnail_url" => Map.get(data, "thumbnail_url"),
      "photo_count" => Map.get(data, "photo_count", 0)
    }
  end

  defp build_user_variables(data) do
    %{
      "user_id" => Map.get(data, "user_id"),
      "user_name" => Map.get(data, "user_name", "User"),
      "organization_name" => Map.get(data, "organization_name")
    }
  end

  defp extract_location_string(%{"location" => %{"address" => address}}) when is_binary(address) do
    address
  end

  defp extract_location_string(%{"location" => %{"latitude" => lat, "longitude" => lng}}) do
    "#{lat}, #{lng}"
  end

  defp extract_location_string(_), do: "unknown location"

  defp get_notification_title(event_type, channel, _variables) do
    case {event_type, channel} do
      {"post.created", :email} -> "New Item Found"
      {"post.matched", :email} -> "Possible Match Found"
      {"user.registered", :email} -> "Welcome to Findly Now!"
      _ -> "Findly Now Notification"
    end
  end

  defp get_notification_body(event_type, channel, variables) do
    case {event_type, channel} do
      {"post.created", :email} ->
        "A #{Map.get(variables, "item_type", "item")} was found at #{Map.get(variables, "location", "unknown location")}."

      {"post.matched", :email} ->
        "We found a possible match for your #{Map.get(variables, "item_type", "item")}. Check it out!"

      {"user.registered", :email} ->
        "Welcome #{Map.get(variables, "user_name", "")}! Your account has been created successfully."

      _ ->
        "You have a new notification from Findly Now."
    end
  end
end