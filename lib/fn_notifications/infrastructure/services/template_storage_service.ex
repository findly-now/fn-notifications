defmodule FnNotifications.Infrastructure.Services.TemplateStorageService do
  @moduledoc """
  Service for managing notification templates in cloud storage.

  Provides high-level operations for:
  - Email template management (HTML, text, subject)
  - Template versioning and caching
  - Template compilation with variables
  - Asset management (images, stylesheets)
  """

  alias FnNotifications.Infrastructure.Adapters.GcsAdapter
  require Logger

  @template_cache_ttl :timer.minutes(30)

  @doc """
  Store an email template in cloud storage.

  ## Examples

      iex> store_template("welcome", "html", "<html>Welcome {{name}}!</html>")
      {:ok, "templates/welcome.html"}

      iex> store_template("welcome", "text", "Welcome {{name}}!")
      {:ok, "templates/welcome.txt"}
  """
  @spec store_template(String.t(), String.t(), String.t()) ::
    {:ok, String.t()} | {:error, String.t()}
  def store_template(template_name, format, content) when format in ["html", "txt", "subject"] do
    object_name = build_template_path(template_name, format)
    content_type = get_content_type(format)

    case GcsAdapter.upload_file(object_name, content, content_type: content_type) do
      {:ok, _url} ->
        # Invalidate cache for this template
        cache_key = build_cache_key(template_name, format)
        Cachex.del(:template_cache, cache_key)

        Logger.info("Template stored successfully",
          template: template_name,
          format: format,
          path: object_name
        )
        {:ok, object_name}

      {:error, reason} ->
        Logger.error("Failed to store template",
          template: template_name,
          format: format,
          error: reason
        )
        {:error, reason}
    end
  end

  def store_template(_template_name, format, _content) do
    {:error, "Unsupported template format: #{format}"}
  end

  @doc """
  Retrieve and compile a template with variables.

  ## Examples

      iex> get_compiled_template("welcome", "html", %{name: "John", email: "john@example.com"})
      {:ok, "<html>Welcome John!</html>"}
  """
  @spec get_compiled_template(String.t(), String.t(), map()) ::
    {:ok, String.t()} | {:error, String.t()}
  def get_compiled_template(template_name, format, variables \\ %{}) do
    case get_template(template_name, format) do
      {:ok, template_content} ->
        compiled = compile_template(template_content, variables)
        {:ok, compiled}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieve a raw template from storage (with caching).
  """
  @spec get_template(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_template(template_name, format) do
    cache_key = build_cache_key(template_name, format)

    case Cachex.get(:template_cache, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from storage
        fetch_and_cache_template(template_name, format, cache_key)

      {:ok, content} ->
        Logger.debug("Template cache hit", template: template_name, format: format)
        {:ok, content}

      {:error, reason} ->
        Logger.warning("Template cache error, fetching from storage",
          template: template_name,
          error: reason
        )
        fetch_template_from_storage(template_name, format)
    end
  end

  @doc """
  Delete a template from storage.
  """
  @spec delete_template(String.t(), String.t()) :: :ok | {:error, String.t()}
  def delete_template(template_name, format) do
    object_name = build_template_path(template_name, format)

    case GcsAdapter.delete_file(object_name) do
      :ok ->
        # Remove from cache
        cache_key = build_cache_key(template_name, format)
        Cachex.del(:template_cache, cache_key)

        Logger.info("Template deleted successfully",
          template: template_name,
          format: format
        )
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete template",
          template: template_name,
          format: format,
          error: reason
        )
        {:error, reason}
    end
  end

  @doc """
  List all available templates.
  """
  @spec list_templates() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_templates do
    # This would require implementing a list_objects function in GcsAdapter
    # For now, return empty list
    Logger.info("Listing templates (not implemented)")
    {:ok, []}
  end

  @doc """
  Store a static asset (images, CSS, etc.) for use in templates.
  """
  @spec store_asset(String.t(), binary(), String.t()) ::
    {:ok, String.t()} | {:error, String.t()}
  def store_asset(asset_name, content, content_type) do
    object_name = "assets/#{asset_name}"

    case GcsAdapter.upload_file(object_name, content,
           content_type: content_type,
           cache_control: "public, max-age=86400") do
      {:ok, url} ->
        Logger.info("Asset stored successfully", asset: asset_name, url: url)
        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to store asset", asset: asset_name, error: reason)
        {:error, reason}
    end
  end

  # Private functions

  defp build_template_path(template_name, format) do
    extension = case format do
      "html" -> "html"
      "txt" -> "txt"
      "subject" -> "subject.txt"
    end

    "templates/#{template_name}.#{extension}"
  end

  defp build_cache_key(template_name, format) do
    "template:#{template_name}:#{format}"
  end

  defp get_content_type("html"), do: "text/html"
  defp get_content_type("txt"), do: "text/plain"
  defp get_content_type("subject"), do: "text/plain"

  defp fetch_and_cache_template(template_name, format, cache_key) do
    case fetch_template_from_storage(template_name, format) do
      {:ok, content} ->
        # Cache for 30 minutes
        Cachex.put(:template_cache, cache_key, content, ttl: @template_cache_ttl)
        Logger.debug("Template cached", template: template_name, format: format)
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_template_from_storage(template_name, format) do
    object_name = build_template_path(template_name, format)

    case GcsAdapter.download_file(object_name) do
      {:ok, content} ->
        Logger.debug("Template fetched from storage",
          template: template_name,
          format: format
        )
        {:ok, content}

      {:error, reason} ->
        Logger.warning("Template not found in storage",
          template: template_name,
          format: format,
          error: reason
        )
        {:error, reason}
    end
  end

  defp compile_template(template_content, variables) do
    # Simple mustache-style variable replacement: {{variable}}
    Enum.reduce(variables, template_content, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  @doc """
  Initialize the template cache.
  Call this during application startup.
  """
  def start_cache do
    case Cachex.start_link(:template_cache, limit: 1000) do
      {:ok, _pid} ->
        Logger.info("Template cache started successfully")
        :ok

      {:error, {:already_started, _pid}} ->
        Logger.debug("Template cache already started")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start template cache", error: reason)
        {:error, reason}
    end
  end
end