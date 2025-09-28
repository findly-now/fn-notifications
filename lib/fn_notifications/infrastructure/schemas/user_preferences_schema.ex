defmodule FnNotifications.Infrastructure.Schemas.UserPreferencesSchema do
  @moduledoc """
  Ecto schema for user_preferences table with conversion methods to/from domain entities.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FnNotifications.Domain.Entities.UserPreferences

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "user_preferences" do
    field :user_id, :string
    field :global_enabled, :boolean, default: true
    field :email, :string
    field :phone, :string
    field :timezone, :string, default: "UTC"
    field :language, :string, default: "en"
    field :channel_preferences, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset based on the struct and params.
  """
  def changeset(user_preferences, attrs) do
    user_preferences
    |> cast(attrs, [:id, :user_id, :global_enabled, :email, :phone, :timezone, :language, :channel_preferences])
    |> validate_required([:id, :user_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_format(:phone, ~r/^\+[1-9]\d{1,14}$/, message: "must be a valid E.164 format phone number")
    |> validate_inclusion(:language, ["en", "es"])
    |> validate_length(:timezone, min: 1)
    |> validate_length(:email, max: 255)
    |> validate_length(:phone, max: 50)
    |> unique_constraint(:user_id)
  end

  @doc """
  Converts a UserPreferences domain entity to an Ecto changeset for persistence.
  """
  @spec from_entity(UserPreferences.t()) :: Ecto.Changeset.t()
  def from_entity(%UserPreferences{} = user_preferences) do
    attrs = %{
      id: user_preferences.id,
      user_id: user_preferences.user_id,
      global_enabled: user_preferences.global_enabled,
      email: user_preferences.email,
      phone: user_preferences.phone,
      timezone: user_preferences.timezone,
      language: user_preferences.language,
      channel_preferences: serialize_channel_preferences(user_preferences.channel_preferences),
      updated_at: user_preferences.updated_at
    }

    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Converts an Ecto schema to a UserPreferences domain entity.
  """
  @spec to_entity(t()) :: UserPreferences.t()
  def to_entity(%__MODULE__{} = schema) do
    %UserPreferences{
      id: schema.id,
      user_id: schema.user_id,
      global_enabled: schema.global_enabled,
      email: schema.email,
      phone: schema.phone,
      timezone: schema.timezone,
      language: schema.language,
      channel_preferences: deserialize_channel_preferences(schema.channel_preferences),
      updated_at: schema.updated_at
    }
  end

  # Private helper functions
  defp serialize_channel_preferences(channel_prefs) when is_map(channel_prefs) do
    # Convert atom keys to strings for JSON storage
    channel_prefs
    |> Enum.map(fn {channel, prefs} ->
      channel_key = if is_atom(channel), do: Atom.to_string(channel), else: channel
      {channel_key, serialize_channel_preference(prefs)}
    end)
    |> Enum.into(%{})
  end

  defp serialize_channel_preference(%{enabled: enabled} = prefs) do
    base_prefs = %{"enabled" => enabled}

    base_prefs
    |> maybe_add_quiet_hours(prefs[:quiet_hours])
    |> maybe_add_frequency_limit(prefs[:frequency_limit])
  end

  defp serialize_channel_preference(prefs), do: prefs

  defp maybe_add_quiet_hours(prefs, nil), do: prefs

  defp maybe_add_quiet_hours(prefs, %{start: start_time, end: end_time}) do
    Map.put(prefs, "quiet_hours", %{
      "start" => Time.to_string(start_time),
      "end" => Time.to_string(end_time)
    })
  end

  defp maybe_add_frequency_limit(prefs, nil), do: prefs

  defp maybe_add_frequency_limit(prefs, limit) when is_integer(limit) do
    Map.put(prefs, "frequency_limit", limit)
  end

  defp deserialize_channel_preferences(channel_prefs) when is_map(channel_prefs) do
    channel_prefs
    |> Enum.map(fn {channel_str, prefs} ->
      channel_atom = String.to_existing_atom(channel_str)
      {channel_atom, deserialize_channel_preference(prefs)}
    end)
    |> Enum.into(%{})
  rescue
    ArgumentError ->
      # Handle case where string doesn't correspond to existing atom
      %{}
  end

  defp deserialize_channel_preferences(_), do: %{}

  defp deserialize_channel_preference(%{"enabled" => enabled} = prefs) do
    base_prefs = %{enabled: enabled}

    base_prefs
    |> maybe_deserialize_quiet_hours(prefs["quiet_hours"])
    |> maybe_deserialize_frequency_limit(prefs["frequency_limit"])
  end

  defp deserialize_channel_preference(prefs), do: prefs

  defp maybe_deserialize_quiet_hours(prefs, nil), do: prefs

  defp maybe_deserialize_quiet_hours(prefs, %{"start" => start_str, "end" => end_str}) do
    with {:ok, start_time} <- Time.from_iso8601(start_str),
         {:ok, end_time} <- Time.from_iso8601(end_str) do
      Map.put(prefs, :quiet_hours, %{start: start_time, end: end_time})
    else
      _ -> prefs
    end
  end

  defp maybe_deserialize_frequency_limit(prefs, nil), do: prefs

  defp maybe_deserialize_frequency_limit(prefs, limit) when is_integer(limit) do
    Map.put(prefs, :frequency_limit, limit)
  end

  defp maybe_deserialize_frequency_limit(prefs, _), do: prefs
end
