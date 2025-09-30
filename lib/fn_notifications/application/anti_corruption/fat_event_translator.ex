defmodule FnNotifications.Application.AntiCorruption.FatEventTranslator do
  @moduledoc """
  Anti-corruption layer for translating external events to domain commands.

  This module handles the translation of events (events containing complete context
  including user preferences and organization settings) to domain commands. This ensures
  the domain layer remains independent of external schema changes while consuming
  all necessary data from the events themselves.

  ## Events Support
  - Extracts user preferences from event context (no API calls needed)
  - Uses organization settings from event context
  - Processes PrivacySafeUser data instead of raw user info
  - Supports contact exchange workflow events

  ## Event Types Supported
  - Post lifecycle events (post.created, post.matched, post.claimed, etc.)
  - User lifecycle events (user.registered, organization.staff_added)
  - Contact exchange events (contact.exchange.requested, contact.exchange.approved, etc.)
  """

  alias FnNotifications.Application.Commands.SendNotificationCommand
  alias FnNotifications.Application.Commands.SendContactExchangeNotificationCommand

  @type external_event :: map()
  @type domain_command :: SendNotificationCommand.t() | SendContactExchangeNotificationCommand.t()

  @doc """
  Main entry point for translating events to domain commands.
  """
  @spec translate(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate(%{"event_type" => event_type} = event) do
    case String.split(event_type, ".") do
      ["post" | _] -> translate_post_event(event)
      ["contact", "exchange" | _] -> translate_contact_exchange_event(event)
      ["user" | _] -> translate_user_event(event)
      ["organization" | _] -> translate_user_event(event)
      ["notification" | _] -> translate_notification_event(event)
      _ -> {:error, "Unknown event type: #{event_type}"}
    end
  end

  def translate(_event) do
    {:error, "Invalid event format"}
  end

  @doc """
  Translates post lifecycle events.
  """
  @spec translate_post_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_post_event(%{"event_type" => event_type, "data" => data} = event) do
    case event_type do
      "post.created" -> translate_post_created(data, event)
      "post.matched" -> translate_post_matched(data, event)
      "post.claimed" -> translate_post_claimed(data, event)
      "post.resolved" -> translate_post_resolved(data, event)
      _ -> {:error, "Unknown post event type: #{event_type}"}
    end
  end

  @doc """
  Translates contact exchange events from fat events.
  """
  @spec translate_contact_exchange_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_contact_exchange_event(%{"event_type" => event_type, "data" => data} = event) do
    case event_type do
      "contact.exchange.requested" -> translate_contact_exchange_requested(data, event)
      "contact.exchange.approved" -> translate_contact_exchange_approved(data, event)
      "contact.exchange.denied" -> translate_contact_exchange_denied(data, event)
      "contact.exchange.expired" -> translate_contact_exchange_expired(data, event)
      _ -> {:error, "Unknown contact exchange event type: #{event_type}"}
    end
  end

  @doc """
  Translates user lifecycle events from fat events.
  """
  @spec translate_user_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_user_event(%{"event_type" => event_type, "data" => data} = event) do
    case event_type do
      "user.registered" -> translate_user_registered(data, event)
      "organization.staff_added" -> translate_staff_added(data, event)
      _ -> {:error, "Unknown user event type: #{event_type}"}
    end
  end

  @doc """
  Translates matcher events from fat events (compatibility with existing processors).
  """
  @spec translate_matcher_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_matcher_event(%{"event_type" => event_type} = event) do
    case event_type do
      "post.matched" -> translate_post_matched(get_in(event, ["data"]), event)
      "post.claimed" -> translate_post_claimed(get_in(event, ["data"]), event)
      "match.expired" -> translate_match_expired(get_in(event, ["data"]), event)
      _ -> {:error, "Unknown matcher event type: #{event_type}"}
    end
  end

  @doc """
  Translates notification delivery events (for analytics and monitoring).
  """
  @spec translate_notification_event(external_event()) :: {:ok, [domain_command()]} | {:error, String.t()}
  def translate_notification_event(%{"event_type" => _event_type}) do
    # Notification delivery events don't generate new notifications
    {:ok, []}
  end

  # Private translation functions for post events

  defp translate_post_created(%{"post" => post} = _data, event) do
    user_id = post["user_id"]
    user_preferences = extract_user_preferences(event, user_id)

    variables = %{
      "post_id" => post["id"],
      "post_title" => post["title"],
      "post_type" => post["type"],
      "location" => format_location(post["location"]),
      "photo_count" => length(post["photos"] || [])
    }

    commands = [
      build_notification_command_with_preferences(
        user_id,
        user_preferences,
        "post.created",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_matched(%{"involved_users" => involved_users} = data, event) do
    original_poster = involved_users["original_poster"]
    matched_poster = involved_users["matched_poster"]

    variables = %{
      "original_post_id" => data["original_post"]["id"],
      "matched_post_id" => data["matched_post"]["id"],
      "confidence_score" => get_in(data, ["match_analysis", "confidence_score"]),
      "match_reason" => get_in(data, ["match_analysis", "match_reason"])
    }

    commands = [
      build_notification_command_with_preferences(
        original_poster["user_id"],
        original_poster["preferences"],
        "post.matched",
        variables
      ),
      build_notification_command_with_preferences(
        matched_poster["user_id"],
        matched_poster["preferences"],
        "post.matched",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_claimed(%{"post_owner" => post_owner, "claimer" => claimer} = data, event) do
    variables = %{
      "post_id" => data["post"]["id"],
      "post_title" => data["post"]["title"],
      "claimer_name" => claimer["display_name"],
      "claim_message" => get_in(data, ["contact_exchange_request", "message"])
    }

    # Send urgent SMS to post owner
    commands = [
      build_notification_command_with_preferences(
        post_owner["user_id"],
        post_owner["preferences"],
        "post.claimed",
        variables,
        preferred_channel: "sms"
      ),
      # Send confirmation email to claimer
      build_notification_command_with_preferences(
        claimer["user_id"],
        claimer["preferences"],
        "claim.submitted",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_post_resolved(%{"post" => post} = _data, event) do
    user_id = post["user_id"]
    user_preferences = extract_user_preferences(event, user_id)

    variables = %{
      "post_id" => post["id"],
      "post_title" => post["title"],
      "post_type" => post["type"]
    }

    commands = [
      build_notification_command_with_preferences(
        user_id,
        user_preferences,
        "post.resolved",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  # Private translation functions for contact exchange events

  defp translate_contact_exchange_requested(%{"contact_request" => request, "owner" => owner, "requester" => requester, "related_post" => post} = data, event) do
    case SendContactExchangeNotificationCommand.new(%{
      request_id: request["request_id"],
      notification_type: :request_received,
      requester_user_id: requester["user_id"],
      owner_user_id: owner["user_id"],
      related_post_id: post["id"],
      exchange_status: :pending,
      requester_preferences: requester["preferences"],
      owner_preferences: owner["preferences"],
      post_context: post,
      metadata: %{
        "requester_name" => requester["display_name"],
        "post_title" => post["title"],
        "request_message" => request["message"],
        "expires_at" => request["expires_at"]
      }
    }) do
      {:ok, command} -> {:ok, [command]}
      {:error, reason} -> {:error, "Failed to create contact exchange command: #{inspect(reason)}"}
    end
  end

  defp translate_contact_exchange_approved(%{"contact_approval" => approval, "owner" => owner, "requester" => requester, "related_post" => post} = data, event) do
    case SendContactExchangeNotificationCommand.new(%{
      request_id: approval["request_id"],
      notification_type: :approval_granted,
      requester_user_id: requester["user_id"],
      owner_user_id: owner["user_id"],
      related_post_id: post["id"],
      exchange_status: :approved,
      contact_info: approval["contact_info"] || %{},
      expires_at: parse_datetime(approval["expires_at"]),
      requester_preferences: requester["preferences"],
      owner_preferences: owner["preferences"],
      post_context: post,
      metadata: %{
        "owner_name" => owner["display_name"],
        "post_title" => post["title"],
        "approval_type" => approval["approval_type"],
        "owner_message" => get_in(approval, ["contact_info", "message"])
      }
    }) do
      {:ok, command} -> {:ok, [command]}
      {:error, reason} -> {:error, "Failed to create contact exchange command: #{inspect(reason)}"}
    end
  end

  defp translate_contact_exchange_denied(%{"contact_denial" => denial, "owner" => owner, "requester" => requester, "related_post" => post} = data, event) do
    case SendContactExchangeNotificationCommand.new(%{
      request_id: denial["request_id"],
      notification_type: :denial_sent,
      requester_user_id: requester["user_id"],
      owner_user_id: owner["user_id"],
      related_post_id: post["id"],
      exchange_status: :denied,
      requester_preferences: requester["preferences"],
      owner_preferences: owner["preferences"],
      post_context: post,
      metadata: %{
        "post_title" => post["title"],
        "denial_reason" => denial["denial_reason"],
        "denial_message" => denial["denial_message"]
      }
    }) do
      {:ok, command} -> {:ok, [command]}
      {:error, reason} -> {:error, "Failed to create contact exchange command: #{inspect(reason)}"}
    end
  end

  defp translate_contact_exchange_expired(%{"contact_expiration" => expiration, "involved_users" => users, "related_post" => post} = data, event) do
    requester = users["requester"]
    owner = users["owner"]

    case SendContactExchangeNotificationCommand.new(%{
      request_id: expiration["request_id"],
      notification_type: :expiration_notice,
      requester_user_id: requester["user_id"],
      owner_user_id: owner["user_id"],
      related_post_id: post["id"],
      exchange_status: :expired,
      requester_preferences: requester["preferences"] || %{},
      owner_preferences: owner["preferences"] || %{},
      post_context: post,
      metadata: %{
        "post_title" => post["title"],
        "expiration_reason" => expiration["expiration_reason"],
        "original_status" => expiration["original_status"]
      }
    }) do
      {:ok, command} -> {:ok, [command]}
      {:error, reason} -> {:error, "Failed to create contact exchange command: #{inspect(reason)}"}
    end
  end

  # Private translation functions for user events

  defp translate_user_registered(%{"user" => user} = _data, event) do
    user_preferences = user["preferences"] || %{}

    variables = %{
      "user_name" => user["display_name"] || user["name"],
      "organization_name" => get_in(user, ["organization_context", "organization_name"])
    }

    commands = [
      build_notification_command_with_preferences(
        user["user_id"],
        user_preferences,
        "user.registered",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp translate_staff_added(%{"user" => user, "organization" => organization} = _data, event) do
    user_preferences = user["preferences"] || %{}

    variables = %{
      "user_name" => user["display_name"] || user["name"],
      "organization_name" => organization["name"],
      "role" => user["role"]
    }

    commands = [
      build_notification_command_with_preferences(
        user["user_id"],
        user_preferences,
        "organization.staff_added",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  # Helper functions

  defp build_notification_command_with_preferences(user_id, user_preferences, event_type, variables, opts \\ []) do
    preferred_channel = Keyword.get(opts, :preferred_channel, determine_preferred_channel(user_preferences, event_type))

    case SendNotificationCommand.new(%{
      user_id: user_id,
      channel: preferred_channel,
      title: get_notification_title(event_type, preferred_channel, variables),
      body: get_notification_body(event_type, preferred_channel, variables),
      metadata: %{
        event_type: event_type,
        variables: variables,
        user_preferences: user_preferences
      }
    }) do
      {:ok, command} -> command
      {:error, _reason} -> nil
    end
  end

  defp determine_preferred_channel(user_preferences, event_type) do
    channels = user_preferences["notification_channels"] || ["email"]

    case event_type do
      "post.claimed" -> if "sms" in channels, do: "sms", else: "email"
      _ -> if "email" in channels, do: "email", else: List.first(channels, "email")
    end
  end

  defp extract_user_preferences(event, user_id) do
    # For backwards compatibility, try to extract from various locations
    case get_in(event, ["data", "involved_users"]) do
      %{"original_poster" => %{"user_id" => ^user_id, "preferences" => prefs}} -> prefs
      %{"matched_poster" => %{"user_id" => ^user_id, "preferences" => prefs}} -> prefs
      %{"post_owner" => %{"user_id" => ^user_id, "preferences" => prefs}} -> prefs
      %{"claimer" => %{"user_id" => ^user_id, "preferences" => prefs}} -> prefs
      _ -> %{}
    end
  end

  defp format_location(%{"address" => address}) when is_binary(address), do: address
  defp format_location(%{"latitude" => lat, "longitude" => lng}), do: "#{lat}, #{lng}"
  defp format_location(_), do: "Unknown location"

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
  defp parse_datetime(_), do: nil

  defp get_notification_title(event_type, channel, variables) do
    case {event_type, channel} do
      {"post.created", "email"} -> "Your #{variables["post_type"]} post was created successfully"
      {"post.matched", "email"} -> "🎉 Potential match found!"
      {"post.claimed", "sms"} -> "🚨 URGENT: Someone claimed your #{variables["post_type"]}!"
      {"claim.submitted", "email"} -> "Claim submitted successfully"
      {"post.resolved", "email"} -> "✅ Your #{variables["post_type"]} case was resolved"
      {"user.registered", "email"} -> "Welcome to Findly Now!"
      {"organization.staff_added", "email"} -> "Added to #{variables["organization_name"]}"
      _ -> "Findly Now Notification"
    end
  end

  defp translate_match_expired(%{"match_id" => _match_id, "involved_users" => users} = data, event) do
    original_poster = users["original_poster"]
    matched_poster = users["matched_poster"]

    variables = %{
      "match_id" => data["match_id"],
      "original_post_id" => data["original_post_id"],
      "matched_post_id" => data["matched_post_id"],
      "expiration_reason" => data["expiration_reason"]
    }

    commands = [
      build_notification_command_with_preferences(
        original_poster["user_id"],
        original_poster["preferences"],
        "match.expired",
        variables
      ),
      build_notification_command_with_preferences(
        matched_poster["user_id"],
        matched_poster["preferences"],
        "match.expired",
        variables
      )
    ]

    {:ok, Enum.filter(commands, & &1)}
  end

  defp get_notification_body(event_type, channel, variables) do
    case {event_type, channel} do
      {"post.created", "email"} ->
        "Your #{variables["post_type"]} post '#{variables["post_title"]}' at #{variables["location"]} was created successfully. We'll notify you if we find any matches."

      {"post.matched", "email"} ->
        "We found a potential match for your item with #{variables["confidence_score"]}% confidence. " <>
        "Reason: #{variables["match_reason"]}. Please check your dashboard to review the match."

      {"post.claimed", "sms"} ->
        "URGENT: Someone has claimed your #{variables["post_type"]}! " <>
        "Message: #{variables["claim_message"] || "No message provided"}. " <>
        "Please respond immediately to coordinate pickup."

      {"claim.submitted", "email"} ->
        "Your claim for '#{variables["post_title"]}' has been submitted successfully. " <>
        "The item owner will be notified and should contact you soon. " <>
        "Please keep your phone available for coordination."

      {"post.resolved", "email"} ->
        "Great news! Your #{variables["post_type"]} case for '#{variables["post_title"]}' has been resolved. " <>
        "Thank you for using Findly Now to reunite with your item!"

      {"user.registered", "email"} ->
        "Welcome #{variables["user_name"]}! Your account has been created successfully. " <>
        "You can now report lost items and help others find their belongings."

      {"organization.staff_added", "email"} ->
        "You have been added as #{variables["role"]} to #{variables["organization_name"]}. " <>
        "You can now help manage lost and found items for your organization."

      {"match.expired", "email"} ->
        "A match for your item has expired due to no response. " <>
        "The system will continue looking for new matches automatically. " <>
        "You can also check your dashboard for more potential matches."

      _ ->
        "You have a new notification from Findly Now."
    end
  end
end