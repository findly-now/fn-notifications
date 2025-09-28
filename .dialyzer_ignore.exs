[
  # Ignore warnings for external dependencies
  ~r/.*\/deps\/.*/,
  # Ignore specific OTP warnings that can't be fixed
  "No local return for call to erlang:error/1",
  # Ignore warnings in test files for ExUnit.Callbacks
  ~r/.*test.*ExUnit.Callbacks/,
  # Tesla client warnings for dynamic configuration
  ~r/.*tesla.*middleware/
]
