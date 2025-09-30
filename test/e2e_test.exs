defmodule FnNotifications.E2ETest do
  use ExUnit.Case, async: false

  alias FnNotifications.Application.EventHandlers.PostsEventProcessor
  alias FnNotifications.Application.EventHandlers.UsersEventProcessor
  alias FnNotifications.Application.EventHandlers.MatcherEventProcessor
  alias FnNotifications.Domain.Entities.UserPreferences
  alias FnNotifications.Infrastructure.Repositories.{UserPreferencesRepository, NotificationRepository}

  @moduletag :integration

  setup do
    # Checkout database connection for the test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(FnNotifications.Repo)
    :ok
  end

  describe "End-to-End Event Processing" do
    test "post.created event triggers email notification with repository initialization" do
      user_id = "test-user-001"
      preferences = create_test_user_preferences(user_id, %{email: %{enabled: true}})

      # Ensure repository is initialized
      assert {:ok, _} = UserPreferencesRepository.get_by_user_id(user_id)

      event_data = %{
        "event_type" => "post.created",
        "data" => %{
          "post_id" => "post-001",
          "reporter_id" => user_id,
          "item_type" => "lost",
          "location" => %{
            "latitude" => 40.7128,
            "longitude" => -74.0060,
            "address" => "New York, NY"
          },
          "photo_urls" => ["https://test.com/photo.jpg"],
          "thumbnail_url" => "https://test.com/thumb.jpg",
          "photo_count" => 1
        }
      }

      message = create_broadway_message(event_data)
      result = PostsEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify notification was created in repository
      {:ok, notifications} = NotificationRepository.get_by_user_id(user_id)
      assert length(notifications) > 0

      notification = List.first(notifications)
      assert notification.user_id == user_id
      assert notification.channel == :email
    end

    test "user.registered event creates welcome notification and user preferences" do
      user_id = "user-new-001"
      email = "john@example.com"

      event_data = %{
        "event_type" => "user.registered",
        "data" => %{
          "user_id" => user_id,
          "name" => "John Doe",
          "email" => email,
          "preferred_language" => "en",
          "organization_id" => "org-001"
        }
      }

      message = create_broadway_message(event_data)
      result = UsersEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify user preferences were created in repository
      {:ok, preferences} = UserPreferencesRepository.get_by_user_id(user_id)
      assert preferences.email == email
      assert preferences.channel_preferences.email.enabled == true

      # Verify welcome notification was created
      {:ok, notifications} = NotificationRepository.get_by_user_id(user_id)
      welcome_notification = Enum.find(notifications, fn n ->
        String.contains?(n.title, "Welcome") or String.contains?(n.body, "welcome")
      end)
      assert welcome_notification != nil
      assert welcome_notification.channel == :email
    end

    test "post.matched event triggers WhatsApp notification with adapter initialization" do
      user_id = "test-user-match-001"
      preferences = create_test_user_preferences(user_id, %{whatsapp: %{enabled: true}})

      # Verify adapter can access user preferences from repository
      assert {:ok, retrieved_prefs} = UserPreferencesRepository.get_by_user_id(user_id)
      assert retrieved_prefs.phone == preferences.phone

      event_data = %{
        "event_type" => "post.matched",
        "data" => %{
          "post_id" => "post-match-001",
          "matched_item_id" => "item-002",
          "reporter_id" => user_id,
          "match_confidence" => 0.85,
          "photo_urls" => ["https://test.com/match.jpg"],
          "photo_count" => 1
        }
      }

      message = create_broadway_message(event_data)
      result = PostsEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify notification repository interaction
      {:ok, notifications} = NotificationRepository.get_by_user_id(user_id)
      whatsapp_notification = Enum.find(notifications, fn n -> n.channel == :whatsapp end)
      assert whatsapp_notification != nil
    end

    test "post.claimed event triggers SMS notification" do
      user_id = "test-user-claim-001"
      create_test_user_preferences(user_id, %{sms: %{enabled: true}})

      event_data = %{
        "event_type" => "post.claimed",
        "data" => %{
          "post_id" => "post-claim-001",
          "claimer_id" => "claimer-123",
          "reporter_id" => user_id,
          "claim_notes" => "Found at the park"
        }
      }

      message = create_broadway_message(event_data)
      result = PostsEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify SMS notification in repository
      {:ok, notifications} = NotificationRepository.get_by_user_id(user_id)
      sms_notification = Enum.find(notifications, fn n -> n.channel == :sms end)
      assert sms_notification != nil
      assert sms_notification.title =~ "claimed"
    end

    test "post.resolved event triggers multiple channel notifications" do
      user_id = "test-user-resolve-001"
      create_test_user_preferences(user_id, %{
        email: %{enabled: true},
        sms: %{enabled: true},
        whatsapp: %{enabled: true}
      })

      event_data = %{
        "event_type" => "post.resolved",
        "data" => %{
          "post_id" => "post-resolve-001",
          "reporter_id" => user_id,
          "resolver_id" => "resolver-456",
          "resolution_type" => "reunited",
          "feedback_requested" => true
        }
      }

      message = create_broadway_message(event_data)
      result = PostsEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify notifications were created for enabled channels
      {:ok, notifications} = NotificationRepository.get_by_user_id(user_id)
      assert length(notifications) > 0

      # At least one notification should be created
      notification = List.first(notifications)
      assert notification.user_id == user_id
      assert notification.metadata["post_id"] == "post-resolve-001"
    end
  end

  describe "Matcher Event Processing" do
    test "matcher post.matched event triggers notifications for both users" do
      reporter_id = "test-reporter-001"
      matcher_id = "test-matcher-001"

      create_test_user_preferences(reporter_id, %{email: %{enabled: true}})
      create_test_user_preferences(matcher_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "post.matched",
        "data" => %{
          "post_id" => "550e8400-e29b-41d4-a716-446655440000",
          "matched_post_id" => "550e8400-e29b-41d4-a716-446655440001",
          "reporter_id" => reporter_id,
          "matcher_id" => matcher_id,
          "confidence_score" => 0.92,
          "match_reason" => "Location proximity and visual similarity"
        }
      }

      message = create_broadway_message(event_data)
      result = MatcherEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify both users received match notifications
      {:ok, reporter_notifications} = NotificationRepository.get_by_user_id(reporter_id)
      {:ok, matcher_notifications} = NotificationRepository.get_by_user_id(matcher_id)

      assert length(reporter_notifications) > 0
      assert length(matcher_notifications) > 0

      reporter_notification = List.first(reporter_notifications)
      assert reporter_notification.channel == :email
      assert reporter_notification.title =~ "Match Found"

      matcher_notification = List.first(matcher_notifications)
      assert matcher_notification.channel == :email
      assert matcher_notification.title =~ "Match Found"
    end

    test "matcher post.claimed event triggers urgent SMS to reporter and email to claimer" do
      reporter_id = "test-reporter-claim-001"
      claimer_id = "test-claimer-001"

      create_test_user_preferences(reporter_id, %{sms: %{enabled: true}})
      create_test_user_preferences(claimer_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "post.claimed",
        "data" => %{
          "post_id" => "550e8400-e29b-41d4-a716-446655440002",
          "reporter_id" => reporter_id,
          "claimer_id" => claimer_id,
          "claim_message" => "I think this is my lost iPhone!"
        }
      }

      message = create_broadway_message(event_data)
      result = MatcherEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify reporter received urgent SMS
      {:ok, reporter_notifications} = NotificationRepository.get_by_user_id(reporter_id)
      sms_notification = Enum.find(reporter_notifications, fn n -> n.channel == :sms end)
      assert sms_notification != nil
      assert sms_notification.title =~ "URGENT"
      assert sms_notification.title =~ "claimed"

      # Verify claimer received confirmation email
      {:ok, claimer_notifications} = NotificationRepository.get_by_user_id(claimer_id)
      email_notification = Enum.find(claimer_notifications, fn n -> n.channel == :email end)
      assert email_notification != nil
      assert email_notification.title =~ "Claim Submitted"
    end

    test "match.expired event triggers email notifications to both users" do
      reporter_id = "test-reporter-expire-001"
      matcher_id = "test-matcher-expire-001"

      create_test_user_preferences(reporter_id, %{email: %{enabled: true}})
      create_test_user_preferences(matcher_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "match.expired",
        "data" => %{
          "match_id" => "550e8400-e29b-41d4-a716-446655440003",
          "post_id" => "550e8400-e29b-41d4-a716-446655440004",
          "matched_post_id" => "550e8400-e29b-41d4-a716-446655440005",
          "reporter_id" => reporter_id,
          "matcher_id" => matcher_id,
          "expiration_reason" => "No response after 24 hours"
        }
      }

      message = create_broadway_message(event_data)
      result = MatcherEventProcessor.handle_message(:default, message, %{})

      assert is_list(result.data)
      assert result.status == :ok

      # Verify both users received expiration notifications
      {:ok, reporter_notifications} = NotificationRepository.get_by_user_id(reporter_id)
      {:ok, matcher_notifications} = NotificationRepository.get_by_user_id(matcher_id)

      assert length(reporter_notifications) > 0
      assert length(matcher_notifications) > 0

      reporter_notification = List.first(reporter_notifications)
      assert reporter_notification.channel == :email
      assert reporter_notification.title =~ "Match Expired"

      matcher_notification = List.first(matcher_notifications)
      assert matcher_notification.channel == :email
      assert matcher_notification.title =~ "Match Expired"
    end

    test "invalid matcher event type returns error" do
      event_data = %{
        "event_type" => "invalid.matcher.event",
        "data" => %{
          "some" => "data"
        }
      }

      message = create_broadway_message(event_data)
      result = MatcherEventProcessor.handle_message(:default, message, %{})

      assert result.status == :failed
    end
  end

  describe "Contact Exchange Event Processing" do
    test "contact.exchange.requested event triggers notification to post owner" do
      owner_id = "test-owner-001"
      requester_id = "test-requester-001"

      create_test_user_preferences(owner_id, %{email: %{enabled: true}})
      create_test_user_preferences(requester_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "contact.exchange.requested",
        "data" => %{
          "contact_request" => %{
            "request_id" => "req-001",
            "message" => "I believe this is my lost wallet",
            "expires_at" => DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_iso8601()
          },
          "owner" => %{
            "user_id" => owner_id,
            "display_name" => "John Owner",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "requester" => %{
            "user_id" => requester_id,
            "display_name" => "Jane Requester",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "related_post" => %{
            "id" => "post-001",
            "title" => "Black leather wallet",
            "type" => "found"
          }
        }
      }

      message = create_broadway_message(event_data)
      result = FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor.handle_message(:default, message, %{})

      assert result.status == :ok

      # Verify contact exchange notification was created
      case FnNotifications.Application.Services.ContactExchangeNotificationService.find_by_request_id("req-001") do
        {:ok, notification} ->
          assert notification.request_id == "req-001"
          assert notification.owner_user_id == owner_id
          assert notification.requester_user_id == requester_id
          assert notification.notification_type.value == :request_received
          assert notification.exchange_status.value == :pending

        {:error, :not_found} ->
          flunk("Contact exchange notification should have been created")
      end
    end

    test "contact.exchange.approved event triggers notification to requester with encrypted contact" do
      owner_id = "test-owner-002"
      requester_id = "test-requester-002"

      create_test_user_preferences(owner_id, %{email: %{enabled: true}})
      create_test_user_preferences(requester_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "contact.exchange.approved",
        "data" => %{
          "contact_approval" => %{
            "request_id" => "req-002",
            "approval_type" => "full_contact",
            "contact_info" => %{
              "email" => "owner@example.com",
              "phone" => "+1555123456",
              "message" => "Please contact me to arrange pickup"
            },
            "expires_at" => DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_iso8601()
          },
          "owner" => %{
            "user_id" => owner_id,
            "display_name" => "John Owner",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "requester" => %{
            "user_id" => requester_id,
            "display_name" => "Jane Requester",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "related_post" => %{
            "id" => "post-002",
            "title" => "iPhone 12 Pro",
            "type" => "lost"
          }
        }
      }

      message = create_broadway_message(event_data)
      result = FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor.handle_message(:default, message, %{})

      assert result.status == :ok

      # Verify contact exchange notification was created with encrypted contact info
      case FnNotifications.Application.Services.ContactExchangeNotificationService.find_by_request_id("req-002") do
        {:ok, notification} ->
          assert notification.request_id == "req-002"
          assert notification.owner_user_id == owner_id
          assert notification.requester_user_id == requester_id
          assert notification.notification_type.value == :approval_granted
          assert notification.exchange_status.value == :approved
          assert notification.expires_at != nil
          # Contact info should be encrypted (not plain text)
          refute Map.get(notification.contact_info, "email") == "owner@example.com"

        {:error, :not_found} ->
          flunk("Contact exchange notification should have been created")
      end
    end

    test "contact.exchange.denied event triggers notification to requester" do
      owner_id = "test-owner-003"
      requester_id = "test-requester-003"

      create_test_user_preferences(owner_id, %{email: %{enabled: true}})
      create_test_user_preferences(requester_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "contact.exchange.denied",
        "data" => %{
          "contact_denial" => %{
            "request_id" => "req-003",
            "denial_reason" => "insufficient_verification",
            "denial_message" => "Please provide more verification that this is your item"
          },
          "owner" => %{
            "user_id" => owner_id,
            "display_name" => "John Owner",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "requester" => %{
            "user_id" => requester_id,
            "display_name" => "Jane Requester",
            "preferences" => %{
              "timezone" => "UTC",
              "language" => "en",
              "notification_channels" => ["email"]
            }
          },
          "related_post" => %{
            "id" => "post-003",
            "title" => "Blue backpack",
            "type" => "found"
          }
        }
      }

      message = create_broadway_message(event_data)
      result = FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor.handle_message(:default, message, %{})

      assert result.status == :ok

      # Verify contact exchange notification was created
      case FnNotifications.Application.Services.ContactExchangeNotificationService.find_by_request_id("req-003") do
        {:ok, notification} ->
          assert notification.request_id == "req-003"
          assert notification.owner_user_id == owner_id
          assert notification.requester_user_id == requester_id
          assert notification.notification_type.value == :denial_sent
          assert notification.exchange_status.value == :denied
          assert Map.get(notification.metadata, "denial_reason") == "insufficient_verification"

        {:error, :not_found} ->
          flunk("Contact exchange notification should have been created")
      end
    end

    test "contact.exchange.expired event triggers expiration notification" do
      owner_id = "test-owner-004"
      requester_id = "test-requester-004"

      create_test_user_preferences(owner_id, %{email: %{enabled: true}})
      create_test_user_preferences(requester_id, %{email: %{enabled: true}})

      event_data = %{
        "event_type" => "contact.exchange.expired",
        "data" => %{
          "contact_expiration" => %{
            "request_id" => "req-004",
            "expiration_reason" => "time_limit_reached",
            "original_status" => "approved"
          },
          "involved_users" => %{
            "owner" => %{
              "user_id" => owner_id,
              "display_name" => "John Owner",
              "preferences" => %{
                "timezone" => "UTC",
                "language" => "en",
                "notification_channels" => ["email"]
              }
            },
            "requester" => %{
              "user_id" => requester_id,
              "display_name" => "Jane Requester",
              "preferences" => %{
                "timezone" => "UTC",
                "language" => "en",
                "notification_channels" => ["email"]
              }
            }
          },
          "related_post" => %{
            "id" => "post-004",
            "title" => "Silver watch",
            "type" => "lost"
          }
        }
      }

      message = create_broadway_message(event_data)
      result = FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor.handle_message(:default, message, %{})

      assert result.status == :ok

      # Verify contact exchange notification was created
      case FnNotifications.Application.Services.ContactExchangeNotificationService.find_by_request_id("req-004") do
        {:ok, notification} ->
          assert notification.request_id == "req-004"
          assert notification.owner_user_id == owner_id
          assert notification.requester_user_id == requester_id
          assert notification.notification_type.value == :expiration_notice
          assert notification.exchange_status.value == :expired
          assert Map.get(notification.metadata, "expiration_reason") == "time_limit_reached"

        {:error, :not_found} ->
          flunk("Contact exchange notification should have been created")
      end
    end

    test "invalid contact exchange event type returns error" do
      event_data = %{
        "event_type" => "contact.exchange.invalid",
        "data" => %{
          "some" => "data"
        }
      }

      message = create_broadway_message(event_data)
      result = FnNotifications.Application.EventHandlers.ContactExchangeEventProcessor.handle_message(:default, message, %{})

      assert result.status == :failed
    end

    test "contact exchange repository operations work correctly" do
      # Test direct repository operations for contact exchange
      alias FnNotifications.Infrastructure.Repositories.ContactExchangeNotificationRepository
      alias FnNotifications.Domain.Entities.ContactExchangeNotification

      # Create a test contact exchange notification
      {:ok, notification} = ContactExchangeNotification.create_request_notification(%{
        request_id: "repo-test-001",
        requester_user_id: "req-user-001",
        owner_user_id: "owner-user-001",
        related_post_id: "post-repo-001",
        metadata: %{"test" => "data"}
      })

      # Test create
      {:ok, created} = ContactExchangeNotificationRepository.create(notification)
      assert created.id == notification.id
      assert created.request_id == "repo-test-001"

      # Test find by ID
      {:ok, found} = ContactExchangeNotificationRepository.find_by_id(created.id)
      assert found.request_id == "repo-test-001"

      # Test find by request ID
      {:ok, found_by_request} = ContactExchangeNotificationRepository.find_by_request_id("repo-test-001")
      assert found_by_request.id == created.id

      # Test find by user IDs
      {:ok, requester_notifications} = ContactExchangeNotificationRepository.find_by_requester_user_id("req-user-001")
      assert length(requester_notifications) == 1

      {:ok, owner_notifications} = ContactExchangeNotificationRepository.find_by_owner_user_id("owner-user-001")
      assert length(owner_notifications) == 1

      # Test mark as sent
      {:ok, marked_sent} = ContactExchangeNotificationRepository.mark_as_sent(created.id)
      assert marked_sent.notification_sent == true
      assert marked_sent.sent_at != nil
    end
  end

  # Helper functions
  defp create_broadway_message(event_data) do
    # Convert map to JSON string as Broadway expects
    json_data = Jason.encode!(event_data)

    %{
      data: json_data,
      acknowledger: %{},
      batcher: :default,
      batch_key: :default,
      batch_mode: :bulk,
      status: :ok
    }
  end

  defp create_test_user_preferences(user_id, overrides \\ %{}) do
    default_preferences = %{
      email: %{enabled: true},
      sms: %{enabled: false},
      whatsapp: %{enabled: false}
    }

    channel_preferences = Map.merge(default_preferences, overrides)

    {:ok, preferences} = UserPreferences.new("pref-#{user_id}", user_id, %{
      email: "#{user_id}@test.example.com",
      phone: "+1555#{String.pad_leading(String.slice(user_id, -3..-1), 7, "0")}",
      channel_preferences: channel_preferences,
      language: "en",
      timezone: "UTC"
    })

    UserPreferencesRepository.save(preferences)
    preferences
  end
end