defmodule FnNotifications.Application.Services.UserPreferencesService do
  @moduledoc """
  Application service for managing user notification preferences.
  Coordinates between the domain layer and infrastructure.
  """

  alias FnNotifications.Domain.Entities.UserPreferences
  alias FnNotifications.Application.Commands.UpdateUserPreferencesCommand

  require Logger

  @preferences_repository Application.compile_env(:fn_notifications, :preferences_repository)

  @doc """
  Get user preferences by user ID.
  Returns default preferences if none exist.
  """
  @spec get_preferences(String.t()) :: {:ok, UserPreferences.t()} | {:error, atom()}
  def get_preferences(user_id) when is_binary(user_id) do
    case @preferences_repository.get_by_user_id(user_id) do
      {:ok, preferences} ->
        {:ok, preferences}

      {:error, :not_found} ->
        # Return default preferences
        default_preferences = %UserPreferences{
          id: UUID.uuid4(),
          user_id: user_id,
          global_enabled: true,
          timezone: "UTC",
          language: "en",
          channel_preferences: %{},
          updated_at: DateTime.utc_now()
        }

        {:ok, default_preferences}

      {:error, reason} ->
        Logger.error("Failed to fetch user preferences", user_id: user_id, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Update user preferences using a command.
  """
  @spec update_preferences(UpdateUserPreferencesCommand.t()) :: {:ok, UserPreferences.t()} | {:error, atom()}
  def update_preferences(%UpdateUserPreferencesCommand{} = command) do
    # Get existing preferences or create new ones
    case get_preferences(command.user_id) do
      {:ok, existing_preferences} ->
        # Update preferences with new values
        updated_preferences = %UserPreferences{
          existing_preferences
          | global_enabled: get_or_default(command.global_enabled, existing_preferences.global_enabled),
            timezone: get_or_default(command.timezone, existing_preferences.timezone),
            language: get_or_default(command.language, existing_preferences.language),
            channel_preferences:
              merge_channel_preferences(
                existing_preferences.channel_preferences,
                command.channel_preferences
              ),
            updated_at: DateTime.utc_now()
        }

        # Validate and save
        case UserPreferences.validate(updated_preferences) do
          {:ok, valid_preferences} ->
            case @preferences_repository.save(valid_preferences) do
              {:ok, saved_preferences} ->
                Logger.info("User preferences updated", user_id: command.user_id)
                {:ok, saved_preferences}

              {:error, reason} ->
                Logger.error("Failed to save user preferences", user_id: command.user_id, error: reason)
                {:error, :save_failed}
            end

          {:error, reason} ->
            Logger.warning("Invalid user preferences", user_id: command.user_id, error: reason)
            {:error, :invalid_preferences}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create and persist default user preferences.
  """
  @spec create_default_preferences(String.t()) :: {:ok, UserPreferences.t()} | {:error, term()}
  def create_default_preferences(user_id) when is_binary(user_id) do
    default_preferences = %UserPreferences{
      id: UUID.uuid4(),
      user_id: user_id,
      global_enabled: true,
      timezone: "UTC",
      language: "en",
      channel_preferences: %{},
      updated_at: DateTime.utc_now()
    }

    case @preferences_repository.save(default_preferences) do
      {:ok, saved_preferences} ->
        {:ok, saved_preferences}

      error ->
        error
    end
  end

  @doc """
  Reset user preferences to system defaults.
  """
  @spec reset_to_defaults(String.t()) :: {:ok, UserPreferences.t()} | {:error, atom()}
  def reset_to_defaults(user_id) when is_binary(user_id) do
    default_preferences = %UserPreferences{
      id: UUID.uuid4(),
      user_id: user_id,
      global_enabled: true,
      timezone: "UTC",
      language: "en",
      channel_preferences: %{
        "email" => %{"enabled" => true, "quiet_hours" => %{"start" => "22:00", "end" => "07:00"}},
        "sms" => %{"enabled" => true, "quiet_hours" => %{"start" => "22:00", "end" => "07:00"}},
        "whatsapp" => %{"enabled" => false, "quiet_hours" => %{}}
      },
      updated_at: DateTime.utc_now()
    }

    case @preferences_repository.save(default_preferences) do
      {:ok, saved_preferences} ->
        Logger.info("User preferences reset to defaults", user_id: user_id)
        {:ok, saved_preferences}

      {:error, reason} ->
        Logger.error("Failed to reset user preferences", user_id: user_id, error: reason)
        {:error, :reset_failed}
    end
  end

  # Private helper functions

  defp merge_channel_preferences(existing, new) when is_map(existing) and is_map(new) do
    Map.merge(existing, new, fn _key, existing_value, new_value ->
      if is_map(existing_value) and is_map(new_value) do
        Map.merge(existing_value, new_value)
      else
        new_value
      end
    end)
  end

  defp merge_channel_preferences(_existing, new) when is_map(new), do: new
  defp merge_channel_preferences(existing, _new) when is_map(existing), do: existing
  defp merge_channel_preferences(_existing, _new), do: %{}

  # Helper function to properly handle false values instead of using ||
  defp get_or_default(nil, default), do: default
  defp get_or_default(value, _default), do: value
end
