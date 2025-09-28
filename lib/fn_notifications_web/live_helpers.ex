defmodule FnNotificationsWeb.LiveHelpers do
  @moduledoc """
  Shared helper functions for LiveView components and pages.
  Centralizes commonly used functions to avoid duplication across LiveView modules.
  """

  @doc """
  Formats datetime strings for display in UI.

  ## Parameters
  - `datetime_string` - ISO8601 datetime string or nil
  - `format` - Format style: `:short` (default) or `:long`

  ## Examples
      iex> format_datetime("2024-01-15T10:30:00Z")
      "Jan 15, 2024 at 10:30 AM"

      iex> format_datetime("2024-01-15T10:30:00Z", :long)
      "January 15, 2024 at 10:30 AM UTC"
  """
  def format_datetime(datetime_string, format \\ :short)

  def format_datetime(datetime_string, :short) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
      _ -> datetime_string
    end
  end

  def format_datetime(datetime_string, :long) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p %Z")
      _ -> datetime_string
    end
  end

  def format_datetime(_, _), do: "Unknown"

  @doc """
  Returns badge variant class for notification channels.

  ## Examples
      iex> channel_variant("email")
      "info"

      iex> channel_variant("whatsapp")
      "success"
  """
  def channel_variant("email"), do: "info"
  def channel_variant("sms"), do: "warning"
  def channel_variant("whatsapp"), do: "success"
  def channel_variant(_), do: "default"

  @doc """
  Returns badge variant class for notification status.

  ## Examples
      iex> status_variant("delivered")
      "success"

      iex> status_variant("failed")
      "danger"
  """
  def status_variant("pending"), do: "warning"
  def status_variant("sent"), do: "info"
  def status_variant("delivered"), do: "success"
  def status_variant("failed"), do: "danger"
  def status_variant(_), do: "default"

  @doc """
  Checks if notification has associated photos based on metadata.

  ## Examples
      iex> has_photos?(%{metadata: %{"photo_count" => 2}})
      true

      iex> has_photos?(%{metadata: %{}})
      false
  """
  def has_photos?(%{metadata: %{"photo_count" => count}}) when is_integer(count) and count > 0, do: true
  def has_photos?(_), do: false

  @doc """
  Gets photo count from notification metadata.

  ## Examples
      iex> get_photo_count(%{metadata: %{"photo_count" => 3}})
      3

      iex> get_photo_count(%{metadata: %{}})
      0
  """
  def get_photo_count(%{metadata: %{"photo_count" => count}}) when is_integer(count), do: count
  def get_photo_count(_), do: 0

  @doc """
  Gets photo URLs list from notification metadata.

  ## Examples
      iex> get_photo_urls(%{metadata: %{"photo_urls" => ["url1.jpg", "url2.jpg"]}})
      ["url1.jpg", "url2.jpg"]

      iex> get_photo_urls(%{metadata: %{}})
      []
  """
  def get_photo_urls(%{metadata: %{"photo_urls" => urls}}) when is_list(urls), do: urls
  def get_photo_urls(_), do: []

  @doc """
  Checks if notification has a thumbnail URL.

  ## Examples
      iex> has_thumbnail?(%{metadata: %{"thumbnail_url" => "thumb.jpg"}})
      true

      iex> has_thumbnail?(%{metadata: %{"thumbnail_url" => ""}})
      false
  """
  def has_thumbnail?(%{metadata: %{"thumbnail_url" => url}}) when is_binary(url) and url != "", do: true
  def has_thumbnail?(_), do: false

  @doc """
  Formats time for dashboard display (shorter format).

  ## Examples
      iex> format_time("2024-01-15T10:30:00Z")
      "10:30 AM"
  """
  def format_time(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%I:%M %p")
      _ -> "--:--"
    end
  end

  def format_time(_), do: "--:--"
end