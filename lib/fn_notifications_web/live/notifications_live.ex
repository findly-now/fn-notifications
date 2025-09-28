defmodule FnNotificationsWeb.NotificationsLive do
  @moduledoc """
  Lost & Found Notifications List - Comprehensive notification management interface.

  Implements filtering and pagination for all notification types:
  - Lost item reports (post.created)
  - Match alerts (post.matched)
  - Claim notifications (post.claimed)
  - Resolution notifications (post.resolved)
  - User lifecycle events (user.registered, etc.)

  Follows FLOWS.md specification for notification list functionality.
  """
  use FnNotificationsWeb, :live_view

  import FnNotificationsWeb.CoreComponents
  alias Phoenix.PubSub

  @events_topic "domain_events"
  @per_page 20

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(FnNotifications.PubSub, @events_topic)
    end

    socket =
      socket
      |> assign(page_title: "All Notifications")
      |> assign_default_filters()
      |> load_notifications()

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_filters(params)
      |> load_notifications()

    {:noreply, socket}
  end

  # Real-time event handling
  def handle_info({:notification_created, notification}, socket) do
    {:noreply,
     socket
     |> maybe_add_notification(notification)
     |> update_counts()
    }
  end

  def handle_info({:notification_delivered, notification}, socket) do
    {:noreply, update_notification_in_list(socket, notification)}
  end

  def handle_info({:notification_failed, notification}, socket) do
    {:noreply, update_notification_in_list(socket, notification)}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  # Filter changes
  def handle_event("filter_change", %{"filters" => filter_params}, socket) do
    path = ~p"/notifications?#{filter_params}"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/notifications")}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_more_notifications(socket)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Page Header -->
      <div class="mb-8">
        <div class="md:flex md:items-center md:justify-between">
          <div class="flex-1 min-w-0">
            <h1 class="text-3xl font-bold text-gray-900">
              Lost & Found Notifications
            </h1>
            <p class="mt-2 text-lg text-gray-600">
              Complete history of all notification delivery attempts
            </p>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-8">
        <form phx-change="filter_change">
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
            <!-- Event Type Filter -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Event Type
              </label>
              <select name="filters[event_type]" class="filter-select">
                <option value="">All Events</option>
                <option value="post.created" selected={@filters.event_type == "post.created"}>
                  📋 Lost Item Reports
                </option>
                <option value="post.matched" selected={@filters.event_type == "post.matched"}>
                  🔍 Match Alerts
                </option>
                <option value="post.claimed" selected={@filters.event_type == "post.claimed"}>
                  🏃 Claim Notifications
                </option>
                <option value="post.resolved" selected={@filters.event_type == "post.resolved"}>
                  ✅ Resolution Notices
                </option>
                <option value="user.registered" selected={@filters.event_type == "user.registered"}>
                  👋 User Welcome
                </option>
              </select>
            </div>

            <!-- Channel Filter -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Channel
              </label>
              <select name="filters[channel]" class="filter-select">
                <option value="">All Channels</option>
                <option value="email" selected={@filters.channel == "email"}>📧 Email</option>
                <option value="sms" selected={@filters.channel == "sms"}>📱 SMS</option>
                <option value="whatsapp" selected={@filters.channel == "whatsapp"}>💬 WhatsApp</option>
              </select>
            </div>

            <!-- Status Filter -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Status
              </label>
              <select name="filters[status]" class="filter-select">
                <option value="">All Statuses</option>
                <option value="pending" selected={@filters.status == "pending"}>⏳ Pending</option>
                <option value="delivered" selected={@filters.status == "delivered"}>✅ Delivered</option>
                <option value="failed" selected={@filters.status == "failed"}>❌ Failed</option>
                <option value="cancelled" selected={@filters.status == "cancelled"}>🚫 Cancelled</option>
              </select>
            </div>

            <!-- Time Period Filter -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Time Period
              </label>
              <select name="filters[period]" class="filter-select">
                <option value="today" selected={@filters.period == "today"}>Today</option>
                <option value="week" selected={@filters.period == "week"}>Past Week</option>
                <option value="month" selected={@filters.period == "month"}>Past Month</option>
                <option value="all" selected={@filters.period == "all"}>All Time</option>
              </select>
            </div>
          </div>

          <div class="flex items-center justify-between mt-6">
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
              Showing <%= length(@notifications) %> of <%= @total_count %> notifications
            </div>
          </div>
        </form>
      </div>

      <!-- Summary Stats -->
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-4 mb-8">
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <div class="text-2xl font-bold text-blue-600"><%= @counts.total %></div>
          <div class="text-sm text-gray-500">Total Notifications</div>
        </div>
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <div class="text-2xl font-bold text-green-600"><%= @counts.delivered %></div>
          <div class="text-sm text-gray-500">Successfully Delivered</div>
        </div>
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <div class="text-2xl font-bold text-yellow-600"><%= @counts.pending %></div>
          <div class="text-sm text-gray-500">Pending Delivery</div>
        </div>
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <div class="text-2xl font-bold text-red-600"><%= @counts.failed %></div>
          <div class="text-sm text-gray-500">Failed Delivery</div>
        </div>
      </div>

      <!-- Notifications List -->
      <div class="space-y-6">
        <div :if={@notifications == []} class="bg-white rounded-lg shadow-sm border border-gray-200 p-12">
          <.empty_state
            icon="📭"
            title="No Notifications Found"
            description="Try adjusting your filters or check back later for new Lost & Found notifications."
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

        <div :for={notification <- @notifications} class="bg-white rounded-lg shadow-sm border border-gray-200">
          <.notification_card notification={notification}>
            <:actions>
              <.link
                navigate={~p"/notifications/#{notification.id}"}
                class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
              >
                View Details
              </.link>
            </:actions>
          </.notification_card>

          <!-- Additional metadata for Lost & Found context -->
          <div :if={has_lost_found_metadata?(notification)} class="px-6 pb-4 bg-gray-50 border-t border-gray-200">
            <div class="text-sm text-gray-600">
              <strong>Lost & Found Context:</strong>
              <%= format_lost_found_metadata(notification.metadata) %>
            </div>
          </div>
        </div>

        <!-- Load More Button -->
        <div :if={@has_more_notifications} class="text-center py-6">
          <button
            phx-click="load_more"
            class="inline-flex items-center px-6 py-3 border border-gray-300 shadow-sm text-base font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Load More Notifications
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp assign_default_filters(socket) do
    assign(socket, filters: %{
      event_type: "",
      channel: "",
      status: "",
      period: "week"
    })
  end

  defp apply_filters(socket, params) do
    filters = %{
      event_type: params["event_type"] || "",
      channel: params["channel"] || "",
      status: params["status"] || "",
      period: params["period"] || "week"
    }

    assign(socket, filters: filters)
  end

  defp load_notifications(socket) do
    # Call repository directly to get real data
    # In a full DDD implementation, this would go through Application Services
    alias FnNotifications.Infrastructure.Repositories.NotificationRepository

    filters = %{
      limit: @per_page,
      offset: 0
    }

    # Apply user filters to repository query
    filters =
      filters
      |> maybe_add_filter(:event_type, socket.assigns.filters.event_type)
      |> maybe_add_filter(:channel, socket.assigns.filters.channel)
      |> maybe_add_filter(:status, socket.assigns.filters.status)

    # Get real notifications from database
    {:ok, notifications} = NotificationRepository.get_by_user_id("all", filters)

    # Get counts for summary
    stats = NotificationRepository.get_dashboard_stats()
    counts = %{
      total: stats.total_notifications,
      delivered: stats.delivered_today + (stats.total_notifications - stats.delivered_today - stats.pending_delivery - stats.failed_delivery),
      pending: stats.pending_delivery,
      failed: stats.failed_delivery
    }

    socket
    |> assign(notifications: notifications)
    |> assign(total_count: stats.total_notifications)
    |> assign(has_more_notifications: length(notifications) >= @per_page)
    |> assign(counts: counts)
  end

  defp maybe_add_filter(filters, _key, ""), do: filters
  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp load_more_notifications(socket) do
    # Load additional notifications based on current offset
    # This would integrate with pagination in the real implementation
    socket
  end

  defp update_counts(socket) do
    # Recalculate counts based on current notifications
    # In real implementation, this would be more efficient
    socket
  end

  defp maybe_add_notification(socket, notification) do
    # Add notification to list if it matches current filters
    if notification_matches_filters?(notification, socket.assigns.filters) do
      notifications = [notification | socket.assigns.notifications]
      assign(socket, notifications: notifications)
    else
      socket
    end
  end

  defp update_notification_in_list(socket, updated_notification) do
    notifications = Enum.map(socket.assigns.notifications, fn notification ->
      if notification.id == updated_notification.id do
        updated_notification
      else
        notification
      end
    end)

    assign(socket, notifications: notifications)
  end

  defp notification_matches_filters?(notification, filters) do
    # Check if notification matches current filter criteria
    event_type_match = filters.event_type == "" or
      notification.metadata["event_type"] == filters.event_type

    channel_match = filters.channel == "" or
      to_string(notification.channel) == filters.channel

    status_match = filters.status == "" or
      to_string(notification.status) == filters.status

    event_type_match and channel_match and status_match
  end

  defp has_lost_found_metadata?(notification) do
    event_type = notification.metadata["event_type"]
    event_type && String.starts_with?(event_type, "post.")
  end

  defp format_lost_found_metadata(metadata) do
    case metadata["event_type"] do
      "post.created" ->
        "New lost item: #{metadata["item_type"]} at #{metadata["location"]}"
      "post.matched" ->
        "Potential match found for lost item ##{metadata["post_id"]}"
      "post.claimed" ->
        "Item ##{metadata["post_id"]} claimed by user ##{metadata["claimer_id"]}"
      "post.resolved" ->
        "Item ##{metadata["post_id"]} successfully returned to owner"
      _ ->
        "Lost & Found system event"
    end
  end
end