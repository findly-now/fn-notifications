defmodule FnNotifications.Domain.Entities.UserPreferences do
  @moduledoc """
  User notification preferences entity.
  """

  alias FnNotifications.Domain.ValueObjects.NotificationChannel

  @type channel_preference :: %{
          enabled: boolean(),
          quiet_hours: %{start: Time.t(), end: Time.t()} | nil,
          frequency_limit: pos_integer() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          global_enabled: boolean(),
          email: String.t() | nil,
          phone: String.t() | nil,
          timezone: String.t(),
          language: String.t(),
          channel_preferences: %{NotificationChannel.t() => channel_preference()},
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :user_id]
  defstruct [
    :id,
    :user_id,
    :email,
    :phone,
    :updated_at,
    global_enabled: true,
    timezone: "UTC",
    language: "en",
    channel_preferences: %{}
  ]

  @doc """
  Creates new user preferences.
  """
  @spec new(String.t(), String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def new(id, user_id, attrs \\ %{}) do
    with {:ok, timezone} <- validate_timezone(attrs[:timezone] || "UTC"),
         {:ok, language} <- validate_language(attrs[:language] || "en"),
         {:ok, email} <- validate_email(attrs[:email]),
         {:ok, phone} <- validate_phone(attrs[:phone]),
         {:ok, channel_prefs} <- validate_channel_preferences(attrs[:channel_preferences] || %{}) do
      preferences = %__MODULE__{
        id: id,
        user_id: user_id,
        global_enabled: Map.get(attrs, :global_enabled, true),
        email: email,
        phone: phone,
        timezone: timezone,
        language: language,
        channel_preferences: channel_prefs,
        updated_at: DateTime.utc_now()
      }

      {:ok, preferences}
    end
  end

  @doc """
  Updates global notification enablement.
  """
  @spec update_global_enabled(t(), boolean()) :: t()
  def update_global_enabled(%__MODULE__{} = preferences, enabled) do
    %{preferences | global_enabled: enabled, updated_at: DateTime.utc_now()}
  end

  @doc """
  Updates timezone preference.
  """
  @spec update_timezone(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def update_timezone(%__MODULE__{} = preferences, timezone) do
    case validate_timezone(timezone) do
      {:ok, validated_timezone} ->
        {:ok, %{preferences | timezone: validated_timezone, updated_at: DateTime.utc_now()}}

      error ->
        error
    end
  end

  @doc """
  Updates language preference.
  """
  @spec update_language(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def update_language(%__MODULE__{} = preferences, language) do
    case validate_language(language) do
      {:ok, validated_language} ->
        {:ok, %{preferences | language: validated_language, updated_at: DateTime.utc_now()}}

      error ->
        error
    end
  end

  @doc """
  Updates email address.
  """
  @spec update_email(t(), String.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def update_email(%__MODULE__{} = preferences, email) do
    case validate_email(email) do
      {:ok, validated_email} ->
        {:ok, %{preferences | email: validated_email, updated_at: DateTime.utc_now()}}

      error ->
        error
    end
  end

  @doc """
  Updates phone number.
  """
  @spec update_phone(t(), String.t() | nil) :: {:ok, t()} | {:error, String.t()}
  def update_phone(%__MODULE__{} = preferences, phone) do
    case validate_phone(phone) do
      {:ok, validated_phone} ->
        {:ok, %{preferences | phone: validated_phone, updated_at: DateTime.utc_now()}}

      error ->
        error
    end
  end

  @doc """
  Updates channel preference.
  """
  @spec update_channel_preference(t(), NotificationChannel.t(), channel_preference()) ::
          {:ok, t()} | {:error, String.t()}
  def update_channel_preference(%__MODULE__{channel_preferences: channel_prefs} = preferences, channel, preference) do
    if NotificationChannel.valid?(channel) do
      new_channel_prefs = Map.put(channel_prefs, channel, preference)
      {:ok, %{preferences | channel_preferences: new_channel_prefs, updated_at: DateTime.utc_now()}}
    else
      {:error, "Invalid notification channel"}
    end
  end

  @doc """
  Checks if notifications are allowed for a channel.
  """
  @spec channel_enabled?(t(), NotificationChannel.t()) :: boolean()
  def channel_enabled?(%__MODULE__{global_enabled: false}, _channel), do: false

  def channel_enabled?(%__MODULE__{channel_preferences: channel_prefs}, channel) do
    case Map.get(channel_prefs, channel) do
      # Default to enabled if no specific preference
      nil -> true
      %{enabled: enabled} -> enabled
    end
  end

  @doc """
  Checks if notifications are allowed during current time (considering quiet hours).
  """
  @spec notifications_allowed_now?(t(), NotificationChannel.t()) :: boolean()
  def notifications_allowed_now?(%__MODULE__{} = preferences, channel) do
    if channel_enabled?(preferences, channel) do
      not in_quiet_hours?(preferences, channel)
    else
      false
    end
  end

  @doc """
  Gets the quiet hours for a specific channel.
  """
  @spec get_quiet_hours(t(), NotificationChannel.t()) :: {Time.t(), Time.t()} | nil
  def get_quiet_hours(%__MODULE__{channel_preferences: channel_prefs}, channel) do
    case Map.get(channel_prefs, channel) do
      %{quiet_hours: %{start: start_time, end: end_time}} -> {start_time, end_time}
      _ -> nil
    end
  end

  @doc """
  Gets the frequency limit for a specific channel.
  """
  @spec get_frequency_limit(t(), NotificationChannel.t()) :: pos_integer() | nil
  def get_frequency_limit(%__MODULE__{channel_preferences: channel_prefs}, channel) do
    case Map.get(channel_prefs, channel) do
      %{frequency_limit: limit} -> limit
      _ -> nil
    end
  end

  @doc """
  Validates user preferences entity.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = preferences) do
    with {:ok, _} <- validate_timezone(preferences.timezone),
         {:ok, _} <- validate_language(preferences.language),
         {:ok, _} <- validate_email(preferences.email),
         {:ok, _} <- validate_phone(preferences.phone),
         {:ok, _} <- validate_channel_preferences(preferences.channel_preferences) do
      {:ok, preferences}
    end
  end

  # Private helper functions
  defp in_quiet_hours?(%__MODULE__{} = preferences, channel) do
    case get_quiet_hours(preferences, channel) do
      nil ->
        false

      {start_time, end_time} ->
        current_time = current_time_in_user_timezone(preferences)
        time_in_range?(current_time, start_time, end_time)
    end
  end

  defp current_time_in_user_timezone(%__MODULE__{timezone: _timezone}) do
    # For simplicity, using UTC time here
    # In a real implementation, you'd convert to the user's timezone
    DateTime.utc_now() |> DateTime.to_time()
  end

  defp time_in_range?(current_time, start_time, end_time) do
    cond do
      Time.compare(start_time, end_time) == :lt ->
        # Same day range (e.g., 09:00 to 17:00)
        Time.compare(current_time, start_time) != :lt and
          Time.compare(current_time, end_time) == :lt

      Time.compare(start_time, end_time) == :gt ->
        # Across midnight (e.g., 22:00 to 06:00)
        Time.compare(current_time, start_time) != :lt or
          Time.compare(current_time, end_time) == :lt

      true ->
        # start_time == end_time, no quiet hours
        false
    end
  end

  defp validate_timezone("UTC"), do: {:ok, "UTC"}
  defp validate_timezone(timezone) when timezone in ["America/New_York", "America/Los_Angeles", "Europe/London"], do: {:ok, timezone}
  defp validate_timezone(_), do: {:error, "Invalid timezone"}

  defp validate_language(language) when language in ["en", "es"], do: {:ok, language}
  defp validate_language(_), do: {:error, "Invalid language"}

  defp validate_email(nil), do: {:ok, nil}
  defp validate_email(email) when is_binary(email) do
    if Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email) and String.length(email) <= 255 do
      {:ok, email}
    else
      {:error, "Invalid email format"}
    end
  end
  defp validate_email(_), do: {:error, "Email must be a string or nil"}

  defp validate_phone(nil), do: {:ok, nil}
  defp validate_phone(phone) when is_binary(phone) do
    if Regex.match?(~r/^\+[1-9]\d{1,14}$/, phone) and String.length(phone) <= 50 do
      {:ok, phone}
    else
      {:error, "Invalid phone number format - must be E.164 format"}
    end
  end
  defp validate_phone(_), do: {:error, "Phone number must be a string or nil"}

  defp validate_channel_preferences(prefs) when is_map(prefs) do
    # Validate each channel preference
    valid_prefs =
      prefs
      |> Enum.filter(fn {channel, _} -> NotificationChannel.valid?(channel) end)
      |> Enum.into(%{})

    {:ok, valid_prefs}
  end

  defp validate_channel_preferences(_), do: {:error, "Channel preferences must be a map"}
end
