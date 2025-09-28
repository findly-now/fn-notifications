defmodule FnNotifications.Application.Commands.UpdateUserPreferencesCommand do
  @moduledoc """
  Command for updating user notification preferences.
  """


  defstruct [
    :user_id,
    :global_enabled,
    :timezone,
    :language,
    :channel_preferences
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          global_enabled: boolean() | nil,
          timezone: String.t() | nil,
          language: String.t() | nil,
          channel_preferences: map() | nil
        }

  @doc """
  Creates a new UpdateUserPreferencesCommand with validation.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(params) when is_map(params) do
    command = %__MODULE__{
      user_id: get_param(params, :user_id, "user_id"),
      global_enabled: get_param(params, :global_enabled, "global_enabled"),
      timezone: get_param(params, :timezone, "timezone"),
      language: get_param(params, :language, "language"),
      channel_preferences: get_param(params, :channel_preferences, "channel_preferences")
    }

    case validate(command) do
      [] -> {:ok, command}
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates the command parameters.
  """
  @spec validate(t()) :: [String.t()]
  def validate(%__MODULE__{} = command) do
    []
    |> validate_user_id(command.user_id)
    |> validate_global_enabled(command.global_enabled)
    |> validate_timezone(command.timezone)
    |> validate_language(command.language)
    |> validate_channel_preferences(command.channel_preferences)
  end

  defp validate_user_id(errors, nil), do: ["user_id is required" | errors]
  defp validate_user_id(errors, user_id) when is_binary(user_id) and byte_size(user_id) > 0, do: errors
  defp validate_user_id(errors, _), do: ["user_id must be a non-empty string" | errors]

  defp validate_global_enabled(errors, nil), do: errors
  defp validate_global_enabled(errors, value) when is_boolean(value), do: errors
  defp validate_global_enabled(errors, _), do: ["global_enabled must be a boolean" | errors]

  defp validate_timezone(errors, nil), do: errors
  defp validate_timezone(errors, timezone) when timezone in ["UTC", "America/New_York", "Europe/London"], do: errors
  defp validate_timezone(errors, _), do: ["timezone must be a valid timezone" | errors]

  defp validate_language(errors, nil), do: errors
  defp validate_language(errors, language) when language in ["en", "es"], do: errors
  defp validate_language(errors, _), do: ["language must be 'en' or 'es'" | errors]

  defp validate_channel_preferences(errors, nil), do: errors
  defp validate_channel_preferences(errors, prefs) when is_map(prefs), do: errors
  defp validate_channel_preferences(errors, _), do: ["channel_preferences must be a map" | errors]

  # Helper function to properly get parameter values without || operator
  # This ensures false values are preserved
  defp get_param(params, atom_key, string_key) do
    cond do
      Map.has_key?(params, atom_key) -> params[atom_key]
      Map.has_key?(params, string_key) -> params[string_key]
      true -> nil
    end
  end
end
