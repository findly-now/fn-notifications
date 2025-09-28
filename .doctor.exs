%Doctor.Config{
  ignore_modules: [
    FnNotificationsWeb.Endpoint,
    FnNotificationsWeb.Telemetry
  ],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 80,
  min_overall_doc_coverage: 80,
  min_overall_spec_coverage: 75,
  exception_moduledoc_required: true,
  raise_if_no_moduledoc: true,
  struct_type_spec_required: true,
  umbrella: false
}
