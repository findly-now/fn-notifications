defmodule FnNotifications.MixProject do
  use Mix.Project

  def project do
    [
      app: :fn_notifications,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      releases: releases(),
      compilers: Mix.compilers(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {FnNotifications.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix Framework
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},

      # Core DDD Dependencies
      {:broadway, "~> 1.0"},
      {:broadway_kafka, "~> 0.4"},
      {:tesla, "~> 1.7"},
      {:finch, "~> 0.16"},
      {:swoosh, "~> 1.16"},
      {:oban, "~> 2.18"},

      # Observability & Monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:statix, "~> 1.4"},

      # Testing & Code Quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Utilities
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:uuid, "~> 1.1"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Production Essentials
      {:logger_json, "~> 5.1"},
      {:cachex, "~> 3.6"},

      # Cloud Storage (optional)
      {:google_api_storage, "~> 0.34", optional: true},
      {:goth, "~> 1.4", optional: true}
    ]
  end

  # Add aliases for code quality tools
  defp aliases do
    [
      setup: ["deps.get", "assets.setup"],
      "schema.deploy": ["cmd psql \"$DATABASE_URL\" -f schema.sql"],
      "ecto.reset": ["cmd echo 'Use make deploy-schema-postgres to reset cloud database schema'"],
      test: ["test"],
      # Frontend asset compilation
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      docs: ["docs"],

      # Quality & Security
      quality: ["format", "credo --strict", "dialyzer", "sobelow --config", "doctor"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer --halt-exit-status", "sobelow --exit"],
      security: ["sobelow --config"]
    ]
  end

  # Documentation configuration for ExDoc
  defp docs do
    [
      main: "readme",
      name: "FN Notifications",
      source_url: "https://github.com/your-org/fn-notifications",
      homepage_url: "https://github.com/your-org/fn-notifications",
      docs: [
        readme: "README.md",
        main: "readme"
      ],
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        "Domain Layer": [
          ~r/FnNotifications\.Domain\./
        ],
        "Application Layer": [
          ~r/FnNotifications\.Application\./
        ],
        "Infrastructure Layer": [
          ~r/FnNotifications\.Infrastructure\./
        ],
        "Web Layer": [
          ~r/FnNotificationsWeb\./
        ]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ]
    ]
  end

  # Dialyzer static analysis configuration
  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs",
      flags: [:error_handling, :race_conditions, :underspecs]
    ]
  end

  # Release configuration for production deployment
  defp releases do
    [
      fn_notifications: [
        version: "0.1.0",
        applications: [
          fn_notifications: :permanent
        ],
        include_executables_for: [:unix],
        steps: [:assemble, :tar],
        config_providers: [{Config.Reader, {:system, "RELEASE_ROOT", "/config/runtime.exs"}}]
      ]
    ]
  end
end
