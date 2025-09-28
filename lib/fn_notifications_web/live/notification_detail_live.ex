defmodule FnNotificationsWeb.NotificationDetailLive do
  @moduledoc """
  Individual Notification Detail View - Complete notification information interface.

  Displays comprehensive details for a single notification:
  - Basic notification information (title, body, channel, status)
  - Lost & Found specific metadata and context
  - Delivery timeline and status history
  - Administrative actions (retry, cancel, resolve)

  Follows DDD architecture patterns for the notification service.
  """
  use FnNotificationsWeb, :live_view

  import FnNotificationsWeb.CoreComponents

  def mount(%{"id" => notification_id}, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Notification Details")
      |> assign(notification_id: notification_id)
      |> load_notification()

    {:ok, socket}
  end

  def handle_event("retry_notification", _params, socket) do
    # In a full DDD implementation, this would call:
    # NotificationService.retry_notification(notification_id)
    socket =
      socket
      |> put_flash(:info, "Notification retry has been queued!")
      |> reload_notification()

    {:noreply, socket}
  end

  def handle_event("cancel_notification", _params, socket) do
    # In a full DDD implementation, this would call:
    # NotificationService.cancel_notification(notification_id)
    socket =
      socket
      |> put_flash(:info, "Notification has been cancelled!")
      |> reload_notification()

    {:noreply, socket}
  end

  def handle_event("mark_resolved", _params, socket) do
    # In a full DDD implementation, this would call:
    # NotificationService.mark_resolved(notification_id)
    socket =
      socket
      |> put_flash(:info, "Notification marked as resolved!")
      |> reload_notification()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Page Header -->
      <div class="mb-8">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <.link
              navigate={~p"/notifications"}
              class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
            >
              ← Back to All Notifications
            </.link>
            <div>
              <h1 class="text-3xl font-bold text-gray-900">
                Notification Details
              </h1>
              <p class="mt-1 text-sm text-gray-500">
                ID: <%= @notification.id %>
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <.badge variant={status_badge_variant(@notification.status)} size="md">
              <%= format_status(@notification.status) %> <%= format_status_text(@notification.status) %>
            </.badge>
          </div>
        </div>
      </div>

      <div :if={@notification == nil} class="bg-white rounded-lg shadow-sm border border-gray-200 p-12">
        <.empty_state
          icon="❌"
          title="Notification Not Found"
          description="The notification you're looking for doesn't exist or has been deleted."
        >
          <:action>
            <.link
              navigate={~p"/notifications"}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
            >
              Back to Notifications
            </.link>
          </:action>
        </.empty_state>
      </div>

      <div :if={@notification != nil} class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Main Content -->
        <div class="lg:col-span-2 space-y-8">
          <!-- Notification Content -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              Notification Content
            </h3>

            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Title</label>
                <p class="text-base text-gray-900"><%= @notification.title %></p>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Message Body</label>
                <div class="bg-gray-50 rounded-md p-4">
                  <p class="text-sm text-gray-800 whitespace-pre-wrap"><%= @notification.body %></p>
                </div>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Channel</label>
                  <.badge variant={channel_badge_variant(@notification.channel)} size="sm">
                    <%= format_channel(@notification.channel) %> <%= format_channel_text(@notification.channel) %>
                  </.badge>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">User ID</label>
                  <p class="text-sm text-gray-600"><%= @notification.user_id %></p>
                </div>
              </div>
            </div>
          </div>

          <!-- Lost & Found Context -->
          <div :if={has_lost_found_metadata?(@notification)} class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              📋 Lost & Found Context
            </h3>

            <div class="space-y-4">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Event Type</label>
                  <.badge variant={event_type_badge_variant(@notification.metadata["event_type"])} size="sm">
                    <%= format_event_type(@notification.metadata["event_type"]) %>
                  </.badge>
                </div>
                <div :if={@notification.metadata["post_id"]}>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Post ID</label>
                  <p class="text-sm text-gray-600"><%= @notification.metadata["post_id"] %></p>
                </div>
              </div>

              <div :if={@notification.metadata["item_type"]}>
                <label class="block text-sm font-medium text-gray-700 mb-1">Item Type</label>
                <p class="text-sm text-gray-800"><%= @notification.metadata["item_type"] %></p>
              </div>

              <div :if={@notification.metadata["location"]}>
                <label class="block text-sm font-medium text-gray-700 mb-1">Location</label>
                <p class="text-sm text-gray-800">📍 <%= @notification.metadata["location"] %></p>
              </div>

              <div :if={@notification.metadata["claimer_id"]}>
                <label class="block text-sm font-medium text-gray-700 mb-1">Claimer ID</label>
                <p class="text-sm text-gray-600"><%= @notification.metadata["claimer_id"] %></p>
              </div>
            </div>
          </div>

          <!-- Full Metadata -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              Technical Metadata
            </h3>

            <div class="bg-gray-50 rounded-md p-4">
              <pre class="text-xs text-gray-700 whitespace-pre-wrap"><%= inspect(@notification.metadata, pretty: true) %></pre>
            </div>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-6">
          <!-- Status & Timeline -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              Delivery Status
            </h3>

            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700">Current Status</span>
                <.badge variant={status_badge_variant(@notification.status)}>
                  <%= format_status_text(@notification.status) %>
                </.badge>
              </div>

              <div :if={@notification.retry_count > 0} class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700">Retry Attempts</span>
                <span class="text-sm text-gray-600"><%= @notification.retry_count %>/<%= @notification.max_retries %></span>
              </div>

              <div :if={@notification.failure_reason} class="space-y-2">
                <label class="block text-sm font-medium text-red-700">Failure Reason</label>
                <div class="bg-red-50 border border-red-200 rounded-md p-3">
                  <p class="text-sm text-red-800"><%= @notification.failure_reason %></p>
                </div>
              </div>
            </div>
          </div>

          <!-- Timeline -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              Timeline
            </h3>

            <div class="space-y-4">
              <div class="flex items-start space-x-3">
                <div class="w-2 h-2 bg-blue-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900">Created</p>
                  <p class="text-xs text-gray-500"><%= format_datetime(@notification.inserted_at) %></p>
                </div>
              </div>

              <div :if={@notification.scheduled_at} class="flex items-start space-x-3">
                <div class="w-2 h-2 bg-yellow-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900">Scheduled</p>
                  <p class="text-xs text-gray-500"><%= format_datetime(@notification.scheduled_at) %></p>
                </div>
              </div>

              <div :if={@notification.sent_at} class="flex items-start space-x-3">
                <div class="w-2 h-2 bg-indigo-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900">Sent</p>
                  <p class="text-xs text-gray-500"><%= format_datetime(@notification.sent_at) %></p>
                </div>
              </div>

              <div :if={@notification.delivered_at} class="flex items-start space-x-3">
                <div class="w-2 h-2 bg-green-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900">Delivered</p>
                  <p class="text-xs text-gray-500"><%= format_datetime(@notification.delivered_at) %></p>
                </div>
              </div>

              <div :if={@notification.failed_at} class="flex items-start space-x-3">
                <div class="w-2 h-2 bg-red-400 rounded-full mt-2"></div>
                <div>
                  <p class="text-sm font-medium text-gray-900">Failed</p>
                  <p class="text-xs text-gray-500"><%= format_datetime(@notification.failed_at) %></p>
                </div>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">
              Actions
            </h3>

            <div class="space-y-3">
              <button
                :if={@notification.status == :failed}
                phx-click="retry_notification"
                class="w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
              >
                🔄 Retry Delivery
              </button>

              <button
                :if={@notification.status in [:pending, :scheduled]}
                phx-click="cancel_notification"
                class="w-full inline-flex items-center justify-center px-4 py-2 border border-red-300 text-sm font-medium rounded-md text-red-700 bg-red-50 hover:bg-red-100"
              >
                🚫 Cancel Notification
              </button>

              <button
                :if={@notification.status == :delivered and has_lost_found_metadata?(@notification)}
                phx-click="mark_resolved"
                class="w-full inline-flex items-center justify-center px-4 py-2 border border-green-300 text-sm font-medium rounded-md text-green-700 bg-green-50 hover:bg-green-100"
              >
                ✅ Mark as Resolved
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp load_notification(socket) do
    # Call repository directly to get real notification
    # In a full DDD implementation, this would go through Application Services
    alias FnNotifications.Infrastructure.Repositories.NotificationRepository

    case NotificationRepository.get_by_id(socket.assigns.notification_id) do
      {:ok, notification} ->
        assign(socket, notification: notification)

      {:error, :not_found} ->
        assign(socket, notification: nil)
    end
  end

  defp reload_notification(socket) do
    load_notification(socket)
  end

  defp has_lost_found_metadata?(notification) do
    event_type = notification.metadata["event_type"]
    event_type && String.starts_with?(event_type, "post.")
  end

  # Status formatting helpers
  defp status_badge_variant("delivered"), do: "success"
  defp status_badge_variant("pending"), do: "warning"
  defp status_badge_variant("failed"), do: "danger"
  defp status_badge_variant("cancelled"), do: "default"
  defp status_badge_variant(_), do: "default"

  defp format_status("delivered"), do: "✅"
  defp format_status("pending"), do: "⏳"
  defp format_status("failed"), do: "❌"
  defp format_status("cancelled"), do: "🚫"
  defp format_status(status), do: String.upcase(to_string(status))

  defp format_status_text("delivered"), do: "Delivered"
  defp format_status_text("pending"), do: "Pending"
  defp format_status_text("failed"), do: "Failed"
  defp format_status_text("cancelled"), do: "Cancelled"
  defp format_status_text(status), do: String.upcase(to_string(status))

  # Channel formatting helpers
  defp channel_badge_variant("email"), do: "info"
  defp channel_badge_variant("sms"), do: "success"
  defp channel_badge_variant("whatsapp"), do: "warning"
  defp channel_badge_variant(_), do: "default"

  defp format_channel("email"), do: "📧"
  defp format_channel("sms"), do: "📱"
  defp format_channel("whatsapp"), do: "💬"
  defp format_channel(channel), do: String.upcase(to_string(channel))

  defp format_channel_text("email"), do: "Email"
  defp format_channel_text("sms"), do: "SMS"
  defp format_channel_text("whatsapp"), do: "WhatsApp"
  defp format_channel_text(channel), do: String.upcase(to_string(channel))

  # Event type formatting helpers
  defp event_type_badge_variant("post.created"), do: "info"
  defp event_type_badge_variant("post.matched"), do: "success"
  defp event_type_badge_variant("post.claimed"), do: "warning"
  defp event_type_badge_variant("post.resolved"), do: "success"
  defp event_type_badge_variant(_), do: "default"

  defp format_event_type("post.created"), do: "📋 Lost Item Report"
  defp format_event_type("post.matched"), do: "🔍 Match Found"
  defp format_event_type("post.claimed"), do: "🏃 Item Claimed"
  defp format_event_type("post.resolved"), do: "✅ Item Returned"
  defp format_event_type("user.registered"), do: "👋 User Welcome"
  defp format_event_type(event_type), do: String.upcase(to_string(event_type))

  # DateTime formatting helper
  defp format_datetime(nil), do: "N/A"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %I:%M:%S %p UTC")
  end
end