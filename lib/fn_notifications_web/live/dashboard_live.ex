defmodule FnNotificationsWeb.DashboardLive do
  @moduledoc """
  Lost & Found Notification Dashboard - Real-time monitoring interface.

  Implements the business flows documented in FLOWS.md:
  - Lost item reporting notifications (post.created)
  - Match detection alerts (post.matched)
  - Claim processing notifications (post.claimed)
  - Resolution tracking (post.resolved)

  Follows DDD architecture with real-time updates via Phoenix.PubSub.
  """
  use FnNotificationsWeb, :live_view

  import FnNotificationsWeb.CoreComponents
  alias Phoenix.PubSub

  # PubSub topic for real-time domain events
  @events_topic "domain_events"

  def mount(_params, _session, socket) do
    # Subscribe to real-time domain events if connected
    if connected?(socket) do
      PubSub.subscribe(FnNotifications.PubSub, @events_topic)
    end

    socket =
      socket
      |> assign(page_title: "Lost & Found Dashboard")
      |> load_dashboard_data()
      |> assign_last_updated()

    {:ok, socket}
  end

  # Handle real-time domain events from the Lost & Found system
  def handle_info({:notification_created, notification}, socket) do
    {:noreply,
     socket
     |> update_stats_for_new_notification(notification)
     |> add_to_recent_notifications(notification)
     |> assign_last_updated()
    }
  end

  def handle_info({:notification_delivered, notification}, socket) do
    {:noreply,
     socket
     |> update_stats_for_delivery(notification)
     |> update_recent_notification_status(notification)
     |> assign_last_updated()
    }
  end

  def handle_info({:notification_failed, notification}, socket) do
    {:noreply,
     socket
     |> update_stats_for_failure(notification)
     |> update_recent_notification_status(notification)
     |> assign_last_updated()
    }
  end

  def handle_info(_message, socket) do
    # Ignore other domain events
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Dashboard Header -->
      <div class="mb-8">
        <div class="md:flex md:items-center md:justify-between">
          <div class="flex-1 min-w-0">
            <h1 class="text-3xl font-bold text-gray-900">
              Lost & Found Notifications
            </h1>
            <p class="mt-2 text-lg text-gray-600">
              Real-time monitoring of notification delivery for the Findly Now platform
            </p>
          </div>
          <div class="mt-4 flex md:mt-0 md:ml-4">
            <div class="text-sm text-gray-500">
              Last updated: <%= @last_updated %>
            </div>
          </div>
        </div>
      </div>

      <!-- KPI Cards for Lost & Found Business Flows -->
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8">
        <!-- Lost Items Reported Today -->
        <.kpi_card
          title="Items Reported Today"
          value={@stats.lost_items_today}
          icon="📋"
          color="blue"
          subtitle="New lost item notifications"
        />

        <!-- Potential Matches Found -->
        <.kpi_card
          title="Matches Found"
          value={@stats.matches_found}
          icon="🔍"
          color="green"
          subtitle="Potential item matches identified"
        />

        <!-- Claims in Progress -->
        <.kpi_card
          title="Active Claims"
          value={@stats.active_claims}
          icon="🏃"
          color="yellow"
          subtitle="Items currently being claimed"
        />

        <!-- Successfully Resolved -->
        <.kpi_card
          title="Items Recovered"
          value={@stats.items_recovered}
          icon="✅"
          color="green"
          subtitle="Successful reunions completed"
        />
      </div>

      <!-- Secondary KPIs - Delivery Performance -->
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8">
        <.kpi_card
          title="Total Notifications"
          value={@stats.total_notifications}
          icon="📊"
          color="purple"
          subtitle="All notification types"
        />

        <.kpi_card
          title="Delivered Today"
          value={@stats.delivered_today}
          icon="✉️"
          color="green"
          subtitle="Successfully delivered"
        />

        <.kpi_card
          title="Pending Delivery"
          value={@stats.pending_delivery}
          icon="⏳"
          color="yellow"
          subtitle="Queued for delivery"
        />

        <.kpi_card
          title="Delivery Failures"
          value={@stats.failed_delivery}
          icon="❌"
          color="red"
          subtitle="Failed delivery attempts"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Channel Distribution -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-6">
            Notification Channels
          </h3>
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <div class="text-2xl mr-3">📧</div>
                <div>
                  <div class="font-medium text-gray-900">Email</div>
                  <div class="text-sm text-gray-500">Detailed notifications with photos</div>
                </div>
              </div>
              <div class="text-2xl font-bold text-blue-600">
                <%= @stats.email_notifications %>
              </div>
            </div>

            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <div class="text-2xl mr-3">📱</div>
                <div>
                  <div class="font-medium text-gray-900">SMS</div>
                  <div class="text-sm text-gray-500">Urgent claim alerts</div>
                </div>
              </div>
              <div class="text-2xl font-bold text-green-600">
                <%= @stats.sms_notifications %>
              </div>
            </div>

            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <div class="text-2xl mr-3">💬</div>
                <div>
                  <div class="font-medium text-gray-900">WhatsApp</div>
                  <div class="text-sm text-gray-500">Rich media notifications</div>
                </div>
              </div>
              <div class="text-2xl font-bold text-yellow-600">
                <%= @stats.whatsapp_notifications %>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Activity Feed -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-6">
            <h3 class="text-lg font-semibold text-gray-900">
              Recent Activity
            </h3>
            <.link navigate={~p"/notifications"} class="text-sm text-indigo-600 hover:text-indigo-500">
              View all →
            </.link>
          </div>

          <div :if={@recent_notifications == []} class="py-8">
            <.empty_state
              icon="📭"
              title="No Recent Activity"
              description="New Lost & Found notifications will appear here when they're created."
            />
          </div>

          <div :if={@recent_notifications != []} class="space-y-4">
            <div
              :for={notification <- @recent_notifications}
              class="flex items-start space-x-3 p-3 rounded-lg hover:bg-gray-50 transition-colors"
            >
              <div class="flex-shrink-0">
                <div class={[
                  "w-8 h-8 rounded-full flex items-center justify-center text-sm",
                  notification_type_color(notification.metadata["event_type"])
                ]}>
                  <%= notification_type_icon(notification.metadata["event_type"]) %>
                </div>
              </div>

              <div class="flex-1 min-w-0">
                <div class="flex items-center space-x-2 mb-1">
                  <.badge variant={status_badge_variant(notification.status)} size="xs">
                    <%= format_status(notification.status) %>
                  </.badge>
                  <.badge variant={channel_badge_variant(notification.channel)} size="xs">
                    <%= format_channel(notification.channel) %>
                  </.badge>
                </div>

                <p class="text-sm font-medium text-gray-900 truncate">
                  <%= notification.title %>
                </p>
                <p class="text-xs text-gray-500">
                  <%= relative_time(notification.inserted_at) %> • User <%= notification.user_id %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions following DDD patterns

  defp load_dashboard_data(socket) do
    # Call repository directly to get real data
    # In a full DDD implementation, this would go through Application Services
    alias FnNotifications.Infrastructure.Repositories.NotificationRepository

    # Get real statistics from database
    stats = NotificationRepository.get_dashboard_stats()

    # Get real recent notifications (limit to 5 for dashboard)
    recent_notifications = NotificationRepository.get_recent_notifications(5)

    socket
    |> assign(stats: stats)
    |> assign(recent_notifications: recent_notifications)
  end

  defp assign_last_updated(socket) do
    assign(socket, last_updated: Calendar.strftime(DateTime.utc_now(), "%I:%M:%S %p UTC"))
  end

  defp update_stats_for_new_notification(socket, notification) do
    event_type = notification.metadata["event_type"]

    stats = socket.assigns.stats
    updated_stats = case event_type do
      "post.created" -> %{stats | lost_items_today: stats.lost_items_today + 1}
      "post.matched" -> %{stats | matches_found: stats.matches_found + 1}
      "post.claimed" -> %{stats | active_claims: stats.active_claims + 1}
      "post.resolved" -> %{stats | items_recovered: stats.items_recovered + 1}
      _ -> stats
    end

    assign(socket, stats: %{updated_stats | total_notifications: updated_stats.total_notifications + 1})
  end

  defp update_stats_for_delivery(socket, _notification) do
    stats = socket.assigns.stats
    assign(socket, stats: %{stats |
      delivered_today: stats.delivered_today + 1,
      pending_delivery: max(0, stats.pending_delivery - 1)
    })
  end

  defp update_stats_for_failure(socket, _notification) do
    stats = socket.assigns.stats
    assign(socket, stats: %{stats |
      failed_delivery: stats.failed_delivery + 1,
      pending_delivery: max(0, stats.pending_delivery - 1)
    })
  end

  defp add_to_recent_notifications(socket, notification) do
    recent = [notification | socket.assigns.recent_notifications]
    |> Enum.take(5)  # Keep only 5 most recent

    assign(socket, recent_notifications: recent)
  end

  defp update_recent_notification_status(socket, updated_notification) do
    recent = Enum.map(socket.assigns.recent_notifications, fn notification ->
      if notification.id == updated_notification.id do
        updated_notification
      else
        notification
      end
    end)

    assign(socket, recent_notifications: recent)
  end

  # Helper functions for notification display

  defp notification_type_icon("post.created"), do: "📋"
  defp notification_type_icon("post.matched"), do: "🔍"
  defp notification_type_icon("post.claimed"), do: "🏃"
  defp notification_type_icon("post.resolved"), do: "✅"
  defp notification_type_icon("user.registered"), do: "👋"
  defp notification_type_icon(_), do: "📱"

  defp notification_type_color("post.created"), do: "bg-blue-100 text-blue-600"
  defp notification_type_color("post.matched"), do: "bg-green-100 text-green-600"
  defp notification_type_color("post.claimed"), do: "bg-yellow-100 text-yellow-600"
  defp notification_type_color("post.resolved"), do: "bg-green-100 text-green-600"
  defp notification_type_color("user.registered"), do: "bg-purple-100 text-purple-600"
  defp notification_type_color(_), do: "bg-gray-100 text-gray-600"

  defp status_badge_variant("delivered"), do: "success"
  defp status_badge_variant("pending"), do: "warning"
  defp status_badge_variant("failed"), do: "danger"
  defp status_badge_variant(_), do: "default"

  defp channel_badge_variant("email"), do: "info"
  defp channel_badge_variant("sms"), do: "success"
  defp channel_badge_variant("whatsapp"), do: "warning"
  defp channel_badge_variant(_), do: "default"

  defp format_status("delivered"), do: "✅"
  defp format_status("pending"), do: "⏳"
  defp format_status("failed"), do: "❌"
  defp format_status(status), do: String.upcase(to_string(status))

  defp format_channel("email"), do: "📧"
  defp format_channel("sms"), do: "📱"
  defp format_channel("whatsapp"), do: "💬"
  defp format_channel(channel), do: String.upcase(to_string(channel))

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end