defmodule FnNotifications.Application.Services.ContactExchangeTemplateService do
  @moduledoc """
  Template Service for Contact Exchange Notifications

  Manages notification templates specifically for the contact exchange workflow.
  Provides multi-language support, channel-specific formatting, and secure
  contact information handling in templates.

  ## Supported Templates
  - contact_exchange_request: When someone requests contact information
  - contact_exchange_approved: When owner approves contact sharing
  - contact_exchange_denied: When owner denies contact sharing
  - contact_exchange_expired: When contact exchange expires

  ## Template Features
  - Multi-language support (English, Spanish)
  - Channel-specific formatting (email, SMS, WhatsApp)
  - Privacy-safe contact information handling
  - Responsive email templates with branding
  """

  require Logger

  alias FnNotifications.Infrastructure.Services.TemplateStorageService
  alias FnNotifications.Domain.Services.ContactEncryptionService

  @supported_languages ["en", "es"]
  @supported_channels ["email", "sms", "whatsapp"]

  @doc """
  Renders a contact exchange notification template.
  """
  @spec render_template(String.t(), String.t(), String.t(), map()) ::
          {:ok, %{subject: String.t(), body: String.t()}} | {:error, term()}
  def render_template(template_type, channel, language, variables) do
    Logger.debug("Rendering contact exchange template",
      template_type: template_type,
      channel: channel,
      language: language,
      has_contact_info: Map.has_key?(variables, "contact_info")
    )

    with :ok <- validate_template_params(template_type, channel, language),
         {:ok, subject} <- render_subject(template_type, language, variables),
         {:ok, body} <- render_body(template_type, channel, language, variables) do

      Logger.debug("Contact exchange template rendered successfully")

      {:ok, %{subject: subject, body: body}}
    else
      {:error, reason} = error ->
        Logger.error("Failed to render contact exchange template",
          template_type: template_type,
          channel: channel,
          language: language,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Initializes contact exchange templates with default content.
  """
  @spec initialize_default_templates() :: :ok | {:error, term()}
  def initialize_default_templates do
    Logger.info("Initializing default contact exchange templates")

    templates = build_default_templates()

    results =
      templates
      |> Enum.map(fn {name, format, content} ->
        TemplateStorageService.store_template(name, format, content)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        Logger.info("All contact exchange templates initialized successfully")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to initialize some contact exchange templates: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Updates a contact exchange template.
  """
  @spec update_template(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def update_template(template_type, channel, language, content) do
    template_name = build_template_name(template_type, channel, language)
    format = get_template_format(channel)

    TemplateStorageService.store_template(template_name, format, content)
  end

  # Private functions

  defp validate_template_params(template_type, channel, language) do
    cond do
      template_type not in ["contact_exchange_request", "contact_exchange_approved", "contact_exchange_denied", "contact_exchange_expired"] ->
        {:error, :invalid_template_type}

      channel not in @supported_channels ->
        {:error, :invalid_channel}

      language not in @supported_languages ->
        {:error, :invalid_language}

      true ->
        :ok
    end
  end

  defp render_subject(template_type, language, variables) do
    template_name = build_template_name(template_type, "email", language)

    case TemplateStorageService.get_compiled_template(template_name, "subject", variables) do
      {:ok, subject} ->
        {:ok, subject}

      {:error, _reason} ->
        # Fallback to default subject
        {:ok, get_default_subject(template_type, language, variables)}
    end
  end

  defp render_body(template_type, channel, language, variables) do
    template_name = build_template_name(template_type, channel, language)
    format = get_template_format(channel)

    case TemplateStorageService.get_compiled_template(template_name, format, variables) do
      {:ok, body} ->
        {:ok, body}

      {:error, _reason} ->
        # Fallback to default content
        {:ok, get_default_body(template_type, channel, language, variables)}
    end
  end

  defp build_template_name(template_type, channel, language) do
    "#{template_type}_#{channel}_#{language}"
  end

  defp get_template_format("email"), do: "html"
  defp get_template_format(_), do: "txt"

  defp get_default_subject(template_type, language, variables) do
    post_title = Map.get(variables, "post_title", "item")

    case {template_type, language} do
      {"contact_exchange_request", "en"} ->
        "Someone wants to contact you about '#{post_title}'"

      {"contact_exchange_request", "es"} ->
        "Alguien quiere contactarte sobre '#{post_title}'"

      {"contact_exchange_approved", "en"} ->
        "Contact information shared for '#{post_title}'"

      {"contact_exchange_approved", "es"} ->
        "Información de contacto compartida para '#{post_title}'"

      {"contact_exchange_denied", "en"} ->
        "Contact request declined for '#{post_title}'"

      {"contact_exchange_denied", "es"} ->
        "Solicitud de contacto rechazada para '#{post_title}'"

      {"contact_exchange_expired", "en"} ->
        "Contact exchange expired for '#{post_title}'"

      {"contact_exchange_expired", "es"} ->
        "Intercambio de contacto expirado para '#{post_title}'"

      _ ->
        "Findly Now Notification"
    end
  end

  defp get_default_body(template_type, channel, language, variables) do
    post_title = Map.get(variables, "post_title", "your item")
    requester_name = Map.get(variables, "requester_name", "Someone")
    owner_name = Map.get(variables, "owner_name", "The item owner")

    case {template_type, channel, language} do
      # English templates
      {"contact_exchange_request", "email", "en"} ->
        build_request_email_en(requester_name, post_title, variables)

      {"contact_exchange_request", "sms", "en"} ->
        "#{requester_name} wants to contact you about #{post_title}. Check Findly Now app to respond."

      {"contact_exchange_approved", "email", "en"} ->
        build_approval_email_en(owner_name, post_title, variables)

      {"contact_exchange_approved", "sms", "en"} ->
        "Contact approved for #{post_title}! Check Findly Now app for details."

      {"contact_exchange_denied", "email", "en"} ->
        build_denial_email_en(post_title, variables)

      {"contact_exchange_denied", "sms", "en"} ->
        "Contact request for #{post_title} was declined."

      {"contact_exchange_expired", "email", "en"} ->
        build_expiration_email_en(post_title, variables)

      {"contact_exchange_expired", "sms", "en"} ->
        "Contact exchange for #{post_title} has expired."

      # Spanish templates
      {"contact_exchange_request", "email", "es"} ->
        build_request_email_es(requester_name, post_title, variables)

      {"contact_exchange_request", "sms", "es"} ->
        "#{requester_name} quiere contactarte sobre #{post_title}. Revisa la app Findly Now."

      {"contact_exchange_approved", "email", "es"} ->
        build_approval_email_es(owner_name, post_title, variables)

      {"contact_exchange_approved", "sms", "es"} ->
        "Contacto aprobado para #{post_title}! Revisa la app para más detalles."

      {"contact_exchange_denied", "email", "es"} ->
        build_denial_email_es(post_title, variables)

      {"contact_exchange_denied", "sms", "es"} ->
        "Solicitud de contacto para #{post_title} fue rechazada."

      {"contact_exchange_expired", "email", "es"} ->
        build_expiration_email_es(post_title, variables)

      {"contact_exchange_expired", "sms", "es"} ->
        "Intercambio de contacto para #{post_title} ha expirado."

      # Fallback for WhatsApp (use SMS content)
      {template_type, "whatsapp", language} ->
        get_default_body(template_type, "sms", language, variables)

      _ ->
        "You have a new notification from Findly Now."
    end
  end

  # English email templates

  defp build_request_email_en(requester_name, post_title, variables) do
    message = Map.get(variables, "request_message")
    action_url = Map.get(variables, "action_url", "#")

    base_content = """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #2563eb;">Contact Request for Your Item</h2>

      <p>Hello,</p>

      <p><strong>#{requester_name}</strong> would like to contact you about your item:</p>
      <p style="background: #f3f4f6; padding: 15px; border-radius: 8px;">
        <strong>#{post_title}</strong>
      </p>
    """

    message_content =
      if message do
        """
        <p>They included this message:</p>
        <blockquote style="border-left: 3px solid #2563eb; padding-left: 15px; margin: 20px 0; font-style: italic;">
          "#{message}"
        </blockquote>
        """
      else
        ""
      end

    base_content <> message_content <> """
      <p>You can approve or decline this request to share your contact information securely.</p>

      <a href="#{action_url}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin: 20px 0;">
        Review Request
      </a>

      <p style="color: #6b7280; font-size: 14px;">
        For your privacy, contact information is never shared without your explicit approval and expires automatically after 24 hours.
      </p>

      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
      <p style="color: #6b7280; font-size: 12px;">
        Findly Now - Reuniting people with their lost items
      </p>
    </body>
    </html>
    """
  end

  defp build_approval_email_en(owner_name, post_title, variables) do
    contact_info = Map.get(variables, "contact_info", %{})
    action_url = Map.get(variables, "action_url", "#")

    # Decrypt contact info for display (with audit logging)
    contact_display =
      case contact_info do
        %{} when map_size(contact_info) > 0 ->
          # In a real implementation, decrypt the contact info here
          case ContactEncryptionService.decrypt_contact_info(contact_info, "notification_system") do
            {:ok, decrypted} ->
              build_contact_display(decrypted)

            {:error, _} ->
              "Contact information is available in the secure link below."
          end

        _ ->
          "Contact information is available in the secure link below."
      end

    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #059669;">Contact Information Approved!</h2>

      <p>Great news!</p>

      <p><strong>#{owner_name}</strong> has approved your request to share contact information for:</p>
      <p style="background: #f3f4f6; padding: 15px; border-radius: 8px;">
        <strong>#{post_title}</strong>
      </p>

      <div style="background: #f0fdf4; border: 1px solid #bbf7d0; padding: 20px; border-radius: 8px; margin: 20px 0;">
        <h3 style="color: #059669; margin-top: 0;">Contact Information</h3>
        #{contact_display}
      </div>

      <a href="#{action_url}" style="background: #059669; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin: 20px 0;">
        View Full Details
      </a>

      <p style="color: #dc2626; font-weight: bold;">
        ⚠️ This contact information expires in 24 hours for privacy protection.
      </p>

      <p>Please coordinate with the item owner to arrange pickup or return.</p>

      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
      <p style="color: #6b7280; font-size: 12px;">
        Findly Now - Reuniting people with their lost items
      </p>
    </body>
    </html>
    """
  end

  defp build_denial_email_en(post_title, variables) do
    denial_reason = Map.get(variables, "denial_reason", "owner preference")
    action_url = Map.get(variables, "action_url", "#")

    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #dc2626;">Contact Request Declined</h2>

      <p>We're sorry to inform you that your contact request for the following item has been declined:</p>
      <p style="background: #f3f4f6; padding: 15px; border-radius: 8px;">
        <strong>#{post_title}</strong>
      </p>

      <p><strong>Reason:</strong> #{denial_reason}</p>

      <p>Don't worry! You can still try these alternatives:</p>
      <ul>
        <li>Send a message through the platform</li>
        <li>Provide additional verification if requested</li>
        <li>Contact support if you believe this is your item</li>
      </ul>

      <a href="#{action_url}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin: 20px 0;">
        View Item Details
      </a>

      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
      <p style="color: #6b7280; font-size: 12px;">
        Findly Now - Reuniting people with their lost items
      </p>
    </body>
    </html>
    """
  end

  defp build_expiration_email_en(post_title, variables) do
    action_url = Map.get(variables, "action_url", "#")

    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #f59e0b;">Contact Exchange Expired</h2>

      <p>The contact exchange for the following item has expired:</p>
      <p style="background: #f3f4f6; padding: 15px; border-radius: 8px;">
        <strong>#{post_title}</strong>
      </p>

      <p>For privacy protection, shared contact information is no longer accessible.</p>

      <p>If you still need to coordinate about this item, you can:</p>
      <ul>
        <li>Request contact information again</li>
        <li>Use the platform messaging system</li>
        <li>Contact our support team</li>
      </ul>

      <a href="#{action_url}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin: 20px 0;">
        View Item
      </a>

      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
      <p style="color: #6b7280; font-size: 12px;">
        Findly Now - Reuniting people with their lost items
      </p>
    </body>
    </html>
    """
  end

  # Spanish email templates (simplified for brevity)

  defp build_request_email_es(requester_name, post_title, _variables) do
    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #2563eb;">Solicitud de Contacto</h2>
      <p><strong>#{requester_name}</strong> quiere contactarte sobre: <strong>#{post_title}</strong></p>
      <p>Puedes aprobar o rechazar esta solicitud para compartir tu información de contacto de forma segura.</p>
    </body>
    </html>
    """
  end

  defp build_approval_email_es(_owner_name, post_title, _variables) do
    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #059669;">¡Información de Contacto Aprobada!</h2>
      <p>La información de contacto para <strong>#{post_title}</strong> ha sido compartida.</p>
      <p style="color: #dc2626;">⚠️ Esta información expira en 24 horas por protección de privacidad.</p>
    </body>
    </html>
    """
  end

  defp build_denial_email_es(post_title, _variables) do
    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #dc2626;">Solicitud de Contacto Rechazada</h2>
      <p>Tu solicitud de contacto para <strong>#{post_title}</strong> ha sido rechazada.</p>
      <p>Puedes intentar enviar un mensaje a través de la plataforma.</p>
    </body>
    </html>
    """
  end

  defp build_expiration_email_es(post_title, _variables) do
    """
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #f59e0b;">Intercambio de Contacto Expirado</h2>
      <p>El intercambio de contacto para <strong>#{post_title}</strong> ha expirado.</p>
      <p>Por protección de privacidad, la información de contacto ya no está accesible.</p>
    </body>
    </html>
    """
  end

  defp build_contact_display(%{"email" => email} = contact) when is_binary(email) do
    phone = Map.get(contact, "phone")
    message = Map.get(contact, "message")

    contact_methods = [
      if(email, do: "<strong>Email:</strong> #{email}", else: nil),
      if(phone, do: "<strong>Phone:</strong> #{phone}", else: nil)
    ]
    |> Enum.filter(& &1)
    |> Enum.join("<br>")

    message_part =
      if message do
        "<br><br><strong>Message from owner:</strong><br><em>#{message}</em>"
      else
        ""
      end

    contact_methods <> message_part
  end

  defp build_contact_display(_), do: "Contact information is available in the secure link below."

  defp build_default_templates do
    [
      # English templates
      {"contact_exchange_request_email_en", "subject", "Someone wants to contact you about {{post_title}}"},
      {"contact_exchange_request_email_en", "html", build_request_email_en("{{requester_name}}", "{{post_title}}", %{})},

      {"contact_exchange_approved_email_en", "subject", "Contact information shared for {{post_title}}"},
      {"contact_exchange_approved_email_en", "html", build_approval_email_en("{{owner_name}}", "{{post_title}}", %{})},

      {"contact_exchange_denied_email_en", "subject", "Contact request declined for {{post_title}}"},
      {"contact_exchange_denied_email_en", "html", build_denial_email_en("{{post_title}}", %{})},

      {"contact_exchange_expired_email_en", "subject", "Contact exchange expired for {{post_title}}"},
      {"contact_exchange_expired_email_en", "html", build_expiration_email_en("{{post_title}}", %{})},

      # Spanish templates (basic versions)
      {"contact_exchange_request_email_es", "subject", "Alguien quiere contactarte sobre {{post_title}}"},
      {"contact_exchange_request_email_es", "html", build_request_email_es("{{requester_name}}", "{{post_title}}", %{})},

      {"contact_exchange_approved_email_es", "subject", "Información de contacto compartida para {{post_title}}"},
      {"contact_exchange_approved_email_es", "html", build_approval_email_es("{{owner_name}}", "{{post_title}}", %{})},

      {"contact_exchange_denied_email_es", "subject", "Solicitud de contacto rechazada para {{post_title}}"},
      {"contact_exchange_denied_email_es", "html", build_denial_email_es("{{post_title}}", %{})},

      {"contact_exchange_expired_email_es", "subject", "Intercambio de contacto expirado para {{post_title}}"},
      {"contact_exchange_expired_email_es", "html", build_expiration_email_es("{{post_title}}", %{})}
    ]
  end
end