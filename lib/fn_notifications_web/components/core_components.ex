defmodule FnNotificationsWeb.CoreComponents do
  @moduledoc """
  Core UI components for the Lost & Found notification dashboard.
  Following Domain-Driven Design patterns for the Findly Now platform.
  """
  use Phoenix.Component
  use Gettext, backend: FnNotificationsWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices for system messages.
  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :title, :string, default: nil
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, required: false, doc: "optional inner content (defaults to flash message)"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("#flash-#{@kind}")}
      role="alert"
      class={[
        "flash rounded-lg p-4 shadow-lg border-l-4 bg-white",
        @kind == :info && "border-blue-500 text-blue-800",
        @kind == :error && "border-red-500 text-red-800"
      ]}
      {@rest}
    >
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <.icon :if={@kind == :info} name="hero-information-circle" class="h-5 w-5" />
          <.icon :if={@kind == :error} name="hero-exclamation-circle" class="h-5 w-5" />
        </div>
        <div class="ml-3">
          <p :if={@title} class="font-medium"><%= @title %></p>
          <p class={[@title && "text-sm", !@title && "font-medium"]}><%= msg %></p>
        </div>
        <div class="ml-auto pl-3">
          <div class="-mx-1.5 -my-1.5">
            <button
              type="button"
              class="inline-flex rounded-md p-1.5 hover:bg-gray-100 focus:outline-none"
              aria-label={gettext("close")}
            >
              <.icon name="hero-x-mark" class="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash group for multiple flash messages.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash :if={live_flash(@flash, :info)} kind={:info} title="Info" flash={@flash} />
    <.flash :if={live_flash(@flash, :error)} kind={:error} title="Error" flash={@flash} />
    """
  end

  @doc """
  Renders an icon from the Heroicons library.
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a Lost & Found KPI card for dashboard metrics.
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "blue"
  attr :subtitle, :string, default: nil
  attr :class, :string, default: nil

  def kpi_card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-lg shadow-sm border border-gray-200 p-6 transition-transform hover:scale-105",
      @class
    ]}>
      <div class="flex items-center">
        <div class={[
          "flex-shrink-0 rounded-md p-3 text-2xl",
          color_variant(@color)
        ]}>
          <%= @icon %>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">
              <%= @title %>
            </dt>
            <dd class="text-2xl font-bold text-gray-900">
              <%= @value %>
            </dd>
            <dd :if={@subtitle} class="text-xs text-gray-500 mt-1">
              <%= @subtitle %>
            </dd>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a badge for notification channels and status.
  """
  attr :variant, :string, default: "default", values: ~w(default success warning danger info)
  attr :size, :string, default: "sm", values: ~w(xs sm md)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full font-medium",
      badge_size_classes(@size),
      badge_variant_classes(@variant),
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  @doc """
  Renders a Lost & Found notification card.
  """
  attr :notification, :map, required: true
  attr :class, :string, default: nil
  slot :actions

  def notification_card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-lg shadow-sm border border-gray-200 p-6 hover:shadow-md transition-shadow",
      @class
    ]}>
      <div class="flex items-start justify-between">
        <div class="flex-1 min-w-0">
          <!-- Notification badges -->
          <div class="flex items-center space-x-2 mb-3">
            <.badge variant={channel_badge_variant(@notification.channel)}>
              <%= format_channel(@notification.channel) %>
            </.badge>
            <.badge variant={status_badge_variant(@notification.status)}>
              <%= format_status(@notification.status) %>
            </.badge>
          </div>

          <!-- Notification content -->
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            <%= @notification.title %>
          </h3>

          <p class="text-gray-600 mb-3 line-clamp-3">
            <%= @notification.body %>
          </p>

          <!-- Metadata -->
          <div class="text-sm text-gray-500">
            <div class="flex items-center space-x-4">
              <span>User: <%= @notification.user_id %></span>
              <span>•</span>
              <span><%= format_datetime(@notification.inserted_at) %></span>
            </div>
          </div>
        </div>

        <!-- Actions -->
        <div :if={@actions != []} class="ml-6 flex-shrink-0">
          <%= render_slot(@actions) %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state component.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :class, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-12", @class]}>
      <div class="text-6xl mb-4">
        <%= @icon %>
      </div>
      <h3 class="text-lg font-semibold text-gray-900 mb-2">
        <%= @title %>
      </h3>
      <p class="text-gray-500 max-w-md mx-auto mb-6">
        <%= @description %>
      </p>
      <%= render_slot(@action) %>
    </div>
    """
  end

  @doc """
  Show/hide helpers for JavaScript interactions.
  """
  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-out duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-out duration-200", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  # Private helper functions

  defp color_variant("blue"), do: "bg-blue-100 text-blue-600"
  defp color_variant("green"), do: "bg-green-100 text-green-600"
  defp color_variant("yellow"), do: "bg-yellow-100 text-yellow-600"
  defp color_variant("red"), do: "bg-red-100 text-red-600"
  defp color_variant("purple"), do: "bg-purple-100 text-purple-600"
  defp color_variant(_), do: "bg-gray-100 text-gray-600"

  defp badge_size_classes("xs"), do: "px-2 py-0.5 text-xs"
  defp badge_size_classes("sm"), do: "px-2.5 py-0.5 text-xs"
  defp badge_size_classes("md"), do: "px-3 py-1 text-sm"

  defp badge_variant_classes("default"), do: "bg-gray-100 text-gray-800"
  defp badge_variant_classes("success"), do: "bg-green-100 text-green-800"
  defp badge_variant_classes("warning"), do: "bg-yellow-100 text-yellow-800"
  defp badge_variant_classes("danger"), do: "bg-red-100 text-red-800"
  defp badge_variant_classes("info"), do: "bg-blue-100 text-blue-800"

  defp channel_badge_variant("email"), do: "info"
  defp channel_badge_variant("sms"), do: "success"
  defp channel_badge_variant("whatsapp"), do: "warning"
  defp channel_badge_variant(_), do: "default"

  defp status_badge_variant("delivered"), do: "success"
  defp status_badge_variant("pending"), do: "warning"
  defp status_badge_variant("failed"), do: "danger"
  defp status_badge_variant(_), do: "default"

  defp format_channel("email"), do: "📧 Email"
  defp format_channel("sms"), do: "📱 SMS"
  defp format_channel("whatsapp"), do: "💬 WhatsApp"
  defp format_channel(channel), do: String.upcase(to_string(channel))

  defp format_status("delivered"), do: "✅ Delivered"
  defp format_status("pending"), do: "⏳ Pending"
  defp format_status("failed"), do: "❌ Failed"
  defp format_status("cancelled"), do: "🚫 Cancelled"
  defp format_status(status), do: String.upcase(to_string(status))

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end