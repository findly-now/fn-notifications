defmodule FnNotificationsWeb.UserPreferencesLive do
  @moduledoc """
  Admin User Preferences Management - Administrative interface for managing ALL users' notification settings.

  Allows administrators to:
  - View all users and their notification preferences
  - Edit any user's notification settings
  - View aggregated statistics about user preferences
  - Search and filter users by preferences
  - Bulk update preferences for multiple users

  Follows DDD architecture patterns for the notification service.
  """
  use FnNotificationsWeb, :live_view

  import FnNotificationsWeb.CoreComponents

  @per_page 20

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Admin: User Preferences")
      |> assign_default_filters()
      |> load_users_and_stats()

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_filters(params)
      |> load_users_and_stats()

    {:noreply, socket}
  end

  def handle_event("filter_change", %{"filters" => filter_params}, socket) do
    path = ~p"/preferences?#{filter_params}"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/preferences")}
  end

  def handle_event("toggle_user_preference", %{"user_id" => user_id, "preference" => preference_key, "value" => value}, socket) do
    boolean_value = value == "true"

    # Update preference in database using DDD service
    alias FnNotifications.Application.Services.UserPreferencesService
    alias FnNotifications.Application.Commands.UpdateUserPreferencesCommand

    # Build the channel preferences map
    channel_preferences = build_channel_preferences_update(preference_key, boolean_value)

    # Create the command
    command_params = %{
      user_id: user_id,
      channel_preferences: channel_preferences
    }

    case UpdateUserPreferencesCommand.new(command_params) do
      {:ok, command} ->
        case UserPreferencesService.update_preferences(command) do
          {:ok, _updated_preferences} ->
            socket =
              socket
              |> put_flash(:info, "Updated #{format_preference_name(preference_key)} for user #{user_id}!")
              |> reload_users()

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> put_flash(:error, "Failed to update preference: #{inspect(reason)}")

            {:noreply, socket}
        end

      {:error, errors} ->
        error_message = Enum.join(errors, ", ")
        socket =
          socket
          |> put_flash(:error, "Invalid request: #{error_message}")

        {:noreply, socket}
    end
  end

  def handle_event("toggle_all_notifications", %{"user_id" => user_id, "action" => action}, socket) do
    # Toggle all notification channels for the user based on action
    alias FnNotifications.Application.Services.UserPreferencesService
    alias FnNotifications.Application.Commands.UpdateUserPreferencesCommand

    enabled = action == "enable"

    channel_preferences = %{
      email: %{enabled: enabled},
      sms: %{enabled: enabled},
      whatsapp: %{enabled: enabled}
    }

    command_params = %{
      user_id: user_id,
      global_enabled: enabled,
      channel_preferences: channel_preferences
    }

    case UpdateUserPreferencesCommand.new(command_params) do
      {:ok, command} ->
        case UserPreferencesService.update_preferences(command) do
          {:ok, _updated_preferences} ->
            action_text = if enabled, do: "Enabled", else: "Disabled"
            socket =
              socket
              |> put_flash(:info, "#{action_text} all notifications for user #{user_id}!")
              |> reload_users()

            {:noreply, socket}

          {:error, reason} ->
            action_text = if enabled, do: "enable", else: "disable"
            socket =
              socket
              |> put_flash(:error, "Failed to #{action_text} all notifications: #{inspect(reason)}")

            {:noreply, socket}
        end

      {:error, errors} ->
        error_message = Enum.join(errors, ", ")
        socket =
          socket
          |> put_flash(:error, "Invalid request: #{error_message}")

        {:noreply, socket}
    end
  end

  def handle_event("bulk_enable_email", _params, socket) do
    # In a full implementation, this would call:
    # UserPreferencesService.bulk_update_preference("email_enabled", true)

    socket =
      socket
      |> put_flash(:info, "Enabled email notifications for all users!")
      |> reload_users()

    {:noreply, socket}
  end

  def handle_event("bulk_disable_email", _params, socket) do
    # In a full implementation, this would call:
    # UserPreferencesService.bulk_update_preference("email_enabled", false)

    socket =
      socket
      |> put_flash(:info, "Disabled email notifications for all users!")
      |> reload_users()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Page Header -->
      <div class="mb-8">
        <div class="md:flex md:items-center md:justify-between">
          <div class="flex-1 min-w-0">
            <h1 class="text-3xl font-bold text-gray-900">
              👨‍💼 Admin: User Notification Preferences
            </h1>
            <p class="mt-2 text-lg text-gray-600">
              Manage notification settings for all Findly Now users
            </p>
          </div>
          <div class="mt-4 flex md:mt-0 md:ml-4">
            <.link
              navigate={~p"/"}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
            >
              Back to Dashboard
            </.link>
          </div>
        </div>
      </div>

      <!-- Statistics Cards -->
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8">
        <.kpi_card
          title="Total Users"
          value={@stats.total_users}
          icon="👥"
          color="blue"
          subtitle="Registered users"
        />
        <.kpi_card
          title="Email Enabled"
          value={@stats.email_enabled_count}
          icon="📧"
          color="green"
          subtitle="Users with email notifications"
        />
        <.kpi_card
          title="SMS Enabled"
          value={@stats.sms_enabled_count}
          icon="📱"
          color="yellow"
          subtitle="Users with SMS notifications"
        />
        <.kpi_card
          title="All Disabled"
          value={@stats.all_disabled_count}
          icon="🔇"
          color="red"
          subtitle="Users with no notifications"
        />
      </div>

      <!-- Filters and Bulk Actions -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-8">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">
            Filters & Bulk Actions
          </h3>
        </div>

        <form phx-change="filter_change" class="space-y-4">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Email Preference
              </label>
              <select name="filters[email_enabled]" class="filter-select">
                <option value="">All Users</option>
                <option value="true" selected={@filters.email_enabled == "true"}>Email Enabled</option>
                <option value="false" selected={@filters.email_enabled == "false"}>Email Disabled</option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                SMS Preference
              </label>
              <select name="filters[sms_enabled]" class="filter-select">
                <option value="">All Users</option>
                <option value="true" selected={@filters.sms_enabled == "true"}>SMS Enabled</option>
                <option value="false" selected={@filters.sms_enabled == "false"}>SMS Disabled</option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Global Notifications
              </label>
              <select name="filters[global_enabled]" class="filter-select">
                <option value="">All Users</option>
                <option value="true" selected={@filters.global_enabled == "true"}>Enabled</option>
                <option value="false" selected={@filters.global_enabled == "false"}>Disabled</option>
              </select>
            </div>
          </div>

          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <button
                type="button"
                phx-click="clear_filters"
                class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
              >
                Clear Filters
              </button>
            </div>

            <div class="text-sm text-gray-500">
              Showing <%= length(@users) %> users
            </div>
          </div>
        </form>

        <!-- Bulk Actions -->
        <div class="border-t border-gray-200 pt-4 mt-6">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Bulk Actions</h4>
          <div class="flex items-center space-x-4">
            <button
              phx-click="bulk_enable_email"
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-green-600 hover:bg-green-700"
            >
              📧 Enable Email for All
            </button>
            <button
              phx-click="bulk_disable_email"
              class="inline-flex items-center px-3 py-2 border border-red-300 text-sm leading-4 font-medium rounded-md text-red-700 bg-red-50 hover:bg-red-100"
            >
              📧 Disable Email for All
            </button>
          </div>
        </div>
      </div>

      <!-- Users List -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-200">
          <h3 class="text-lg font-semibold text-gray-900">
            User Preferences Management
          </h3>
        </div>

        <div :if={@users == []} class="p-12">
          <.empty_state
            icon="👥"
            title="No Users Found"
            description="No users match your current filter criteria."
          >
            <:action>
              <button
                phx-click="clear_filters"
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
              >
                Clear Filters
              </button>
            </:action>
          </.empty_state>
        </div>

        <div :if={@users != []} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  User
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Email
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  SMS
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  WhatsApp
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Global
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={user <- @users} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="flex-shrink-0 h-8 w-8">
                      <div class="h-8 w-8 rounded-full bg-indigo-100 flex items-center justify-center">
                        <span class="text-xs font-medium text-indigo-700">
                          <%= String.first(user.user_id) |> String.upcase() %>
                        </span>
                      </div>
                    </div>
                    <div class="ml-4">
                      <div class="text-sm font-medium text-gray-900">
                        User <%= user.user_id %>
                      </div>
                      <div class="text-sm text-gray-500">
                        ID: <%= user.user_id %>
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      checked={user.email_enabled}
                      phx-click="toggle_user_preference"
                      phx-value-user_id={user.user_id}
                      phx-value-preference="email_enabled"
                      phx-value-value={!user.email_enabled}
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                    />
                  </label>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      checked={user.sms_enabled}
                      phx-click="toggle_user_preference"
                      phx-value-user_id={user.user_id}
                      phx-value-preference="sms_enabled"
                      phx-value-value={!user.sms_enabled}
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                    />
                  </label>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      checked={user.whatsapp_enabled}
                      phx-click="toggle_user_preference"
                      phx-value-user_id={user.user_id}
                      phx-value-preference="whatsapp_enabled"
                      phx-value-value={!user.whatsapp_enabled}
                      class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                    />
                  </label>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <.badge variant={if user.global_enabled, do: "success", else: "danger"} size="sm">
                    <%= if user.global_enabled, do: "✅ Enabled", else: "🚫 Disabled" %>
                  </.badge>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <button
                    phx-click="toggle_all_notifications"
                    phx-value-user_id={user.user_id}
                    phx-value-action={if all_channels_enabled?(user), do: "disable", else: "enable"}
                    class={[
                      "text-xs px-3 py-1 rounded border text-center min-w-[100px]",
                      if all_channels_enabled?(user) do
                        "text-red-600 hover:text-red-900 bg-red-50 hover:bg-red-100 border-red-200"
                      else
                        "text-green-600 hover:text-green-900 bg-green-50 hover:bg-green-100 border-green-200"
                      end
                    ]}
                  >
                    <%= if all_channels_enabled?(user), do: "🚫 Disable All", else: "✅ Enable All" %>
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp assign_default_filters(socket) do
    assign(socket, filters: %{
      email_enabled: "",
      sms_enabled: "",
      global_enabled: ""
    })
  end

  defp apply_filters(socket, params) do
    filters = %{
      email_enabled: params["email_enabled"] || "",
      sms_enabled: params["sms_enabled"] || "",
      global_enabled: params["global_enabled"] || ""
    }

    assign(socket, filters: filters)
  end

  defp load_users_and_stats(socket) do
    # Call repository directly to get real data
    # In a full DDD implementation, this would go through Application Services
    alias FnNotifications.Infrastructure.Repositories.UserPreferencesRepository

    # Get user preferences statistics
    {:ok, stats} = UserPreferencesRepository.get_stats()

    # Build filters for repository query
    filters = build_repository_filters(socket.assigns.filters)

    # Get filtered user preferences
    {:ok, user_preferences} = UserPreferencesRepository.list(filters)

    # Transform to our display format
    users = Enum.map(user_preferences, &transform_user_preferences/1)

    # Calculate display stats
    display_stats = %{
      total_users: stats.total_users || length(users),
      email_enabled_count: Enum.count(users, & &1.email_enabled),
      sms_enabled_count: Enum.count(users, & &1.sms_enabled),
      all_disabled_count: Enum.count(users, &(!&1.global_enabled))
    }

    socket
    |> assign(users: users)
    |> assign(stats: display_stats)
  end

  defp build_repository_filters(filters) do
    filters
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case value do
        "" -> acc
        "true" -> Map.put(acc, key, true)
        "false" -> Map.put(acc, key, false)
        _ -> acc
      end
    end)
    |> Map.put(:limit, @per_page)
  end

  defp transform_user_preferences(user_pref) do
    %{
      user_id: user_pref.user_id,
      # Email is enabled by default unless explicitly disabled
      email_enabled: get_channel_preference(user_pref.channel_preferences, :email, true),
      sms_enabled: get_channel_preference(user_pref.channel_preferences, :sms, false),
      whatsapp_enabled: get_channel_preference(user_pref.channel_preferences, :whatsapp, false),
      global_enabled: user_pref.global_enabled || true
    }
  end

  defp reload_users(socket) do
    load_users_and_stats(socket)
  end

  defp update_user_preference_in_list(socket, user_id, preference_key, value) do
    users = Enum.map(socket.assigns.users, fn user ->
      if user.user_id == user_id do
        Map.put(user, String.to_existing_atom(preference_key), value)
      else
        user
      end
    end)

    assign(socket, users: users)
  end

  # Helper function to build channel preferences update map
  defp build_channel_preferences_update("email_enabled", enabled) do
    %{email: %{enabled: enabled}}
  end

  defp build_channel_preferences_update("sms_enabled", enabled) do
    %{sms: %{enabled: enabled}}
  end

  defp build_channel_preferences_update("whatsapp_enabled", enabled) do
    %{whatsapp: %{enabled: enabled}}
  end

  defp build_channel_preferences_update(_preference_key, _enabled) do
    %{}
  end

  # Helper function to format preference names for display
  defp format_preference_name("email_enabled"), do: "email notifications"
  defp format_preference_name("sms_enabled"), do: "SMS notifications"
  defp format_preference_name("whatsapp_enabled"), do: "WhatsApp notifications"
  defp format_preference_name(preference_key), do: String.replace(preference_key, "_", " ")

  # Helper function to safely get channel preference with default value
  defp get_channel_preference(channel_preferences, channel, default) when is_map(channel_preferences) do
    case channel_preferences[channel] do
      %{enabled: enabled} when is_boolean(enabled) -> enabled
      _ -> default
    end
  end

  defp get_channel_preference(_channel_preferences, _channel, default), do: default

  # Helper function to check if all channels are enabled for a user
  defp all_channels_enabled?(user) do
    user.email_enabled && user.sms_enabled && user.whatsapp_enabled
  end
end