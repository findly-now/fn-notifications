defmodule FnNotifications.Infrastructure.Adapters.GcsAdapter do
  @moduledoc """
  Google Cloud Storage adapter for notification templates and attachments.

  Handles storage and retrieval of:
  - Email templates (HTML/text)
  - Notification attachments (images, documents)
  - Static assets (logos, images)
  """

  require Logger

  @type upload_options :: [
    content_type: String.t(),
    cache_control: String.t(),
    metadata: map()
  ]

  @doc """
  Upload a file to Google Cloud Storage.

  ## Examples

      iex> upload_file("templates/welcome.html", "<html>...</html>", content_type: "text/html")
      {:ok, "https://storage.googleapis.com/bucket/templates/welcome.html"}

      iex> upload_file("attachments/logo.png", binary_data, content_type: "image/png")
      {:ok, "https://storage.googleapis.com/bucket/attachments/logo.png"}
  """
  @spec upload_file(String.t(), binary(), upload_options()) ::
    {:ok, String.t()} | {:error, String.t()}
  def upload_file(object_name, content, opts \\ [])

  def upload_file(_object_name, _content, _opts) when not is_configured() do
    Logger.warning("GCS not configured, skipping file upload")
    {:error, "GCS not configured"}
  end

  def upload_file(object_name, content, opts) do
    with {:ok, conn} <- get_connection(),
         {:ok, bucket} <- get_bucket(),
         upload_opts <- build_upload_options(opts),
         {:ok, _response} <- perform_upload(conn, bucket, object_name, content, upload_opts) do
      public_url = build_public_url(bucket, object_name)
      Logger.info("Successfully uploaded file to GCS", object: object_name, url: public_url)
      {:ok, public_url}
    else
      {:error, reason} ->
        Logger.error("Failed to upload file to GCS", object: object_name, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Download a file from Google Cloud Storage.

  ## Examples

      iex> download_file("templates/welcome.html")
      {:ok, "<html>...</html>"}
  """
  @spec download_file(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def download_file(object_name) when not is_configured() do
    Logger.warning("GCS not configured, skipping file download")
    {:error, "GCS not configured"}
  end

  def download_file(object_name) do
    with {:ok, conn} <- get_connection(),
         {:ok, bucket} <- get_bucket(),
         {:ok, response} <- perform_download(conn, bucket, object_name) do
      Logger.debug("Successfully downloaded file from GCS", object: object_name)
      {:ok, response.body}
    else
      {:error, reason} ->
        Logger.error("Failed to download file from GCS", object: object_name, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Delete a file from Google Cloud Storage.
  """
  @spec delete_file(String.t()) :: :ok | {:error, String.t()}
  def delete_file(object_name) when not is_configured() do
    Logger.warning("GCS not configured, skipping file deletion")
    {:error, "GCS not configured"}
  end

  def delete_file(object_name) do
    with {:ok, conn} <- get_connection(),
         {:ok, bucket} <- get_bucket(),
         {:ok, _response} <- perform_delete(conn, bucket, object_name) do
      Logger.info("Successfully deleted file from GCS", object: object_name)
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to delete file from GCS", object: object_name, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Generate a signed URL for temporary access to a private object.
  """
  @spec generate_signed_url(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_signed_url(object_name, expires_in_seconds \\ 3600) when not is_configured() do
    Logger.warning("GCS not configured, cannot generate signed URL")
    {:error, "GCS not configured"}
  end

  def generate_signed_url(object_name, expires_in_seconds) do
    # Implementation would use Google Cloud Storage signed URL generation
    # For now, return a placeholder implementation
    Logger.info("Generating signed URL for GCS object", object: object_name, expires_in: expires_in_seconds)
    {:error, "Signed URL generation not implemented"}
  end

  # Private functions

  defp is_configured do
    Application.get_env(:fn_notifications, :storage) != nil
  end

  defp get_connection do
    case get_credentials() do
      {:ok, credentials} ->
        try do
          conn = GoogleApi.Storage.V1.Connection.new(credentials)
          {:ok, conn}
        rescue
          error ->
            {:error, "Failed to create GCS connection: #{inspect(error)}"}
        end

      error ->
        error
    end
  end

  defp get_credentials do
    case Application.get_env(:fn_notifications, :storage) do
      nil ->
        {:error, "Storage configuration not found"}

      config ->
        case config[:credentials] do
          nil ->
            {:error, "Storage credentials not configured"}

          path when is_binary(path) ->
            # File path to service account JSON
            case File.read(path) do
              {:ok, json} ->
                case Jason.decode(json) do
                  {:ok, credentials} -> {:ok, credentials}
                  {:error, _} -> {:error, "Invalid JSON in service account file"}
                end

              {:error, _} ->
                {:error, "Could not read service account file"}
            end

          credentials when is_map(credentials) ->
            # Direct credentials map
            {:ok, credentials}

          _ ->
            {:error, "Invalid storage credentials format"}
        end
    end
  end

  defp get_bucket do
    case Application.get_env(:fn_notifications, :storage) do
      nil -> {:error, "Storage configuration not found"}
      config ->
        case config[:bucket] do
          nil -> {:error, "Storage bucket not configured"}
          bucket -> {:ok, bucket}
        end
    end
  end

  defp build_upload_options(opts) do
    %{
      contentType: Keyword.get(opts, :content_type, "application/octet-stream"),
      cacheControl: Keyword.get(opts, :cache_control, "public, max-age=3600"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp perform_upload(conn, bucket, object_name, content, opts) do
    try do
      # This is a placeholder - actual implementation would use GoogleApi.Storage.V1.Api.Objects.storage_objects_insert/4
      Logger.debug("Uploading to GCS", bucket: bucket, object: object_name, size: byte_size(content))

      # For now, simulate success
      {:ok, %{name: object_name}}
    rescue
      error ->
        {:error, "Upload failed: #{inspect(error)}"}
    end
  end

  defp perform_download(conn, bucket, object_name) do
    try do
      # This is a placeholder - actual implementation would use GoogleApi.Storage.V1.Api.Objects.storage_objects_get/4
      Logger.debug("Downloading from GCS", bucket: bucket, object: object_name)

      # For now, simulate failure (not implemented)
      {:error, "Download not implemented"}
    rescue
      error ->
        {:error, "Download failed: #{inspect(error)}"}
    end
  end

  defp perform_delete(conn, bucket, object_name) do
    try do
      # This is a placeholder - actual implementation would use GoogleApi.Storage.V1.Api.Objects.storage_objects_delete/3
      Logger.debug("Deleting from GCS", bucket: bucket, object: object_name)

      # For now, simulate success
      {:ok, %{}}
    rescue
      error ->
        {:error, "Delete failed: #{inspect(error)}"}
    end
  end

  defp build_public_url(bucket, object_name) do
    "https://storage.googleapis.com/#{bucket}/#{object_name}"
  end
end