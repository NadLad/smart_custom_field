# Changelog

## 0.1.0 — 2026-10-23

- Initial release, parity with `computed_custom_field` 1.0.7.
- Adds `formula` and `is_computed` columns to `custom_fields`.
- Admin UI: computed checkbox, formula textarea, available fields list.
- Computed values are evaluated before validation and persisted with the
  customized object.
- Computed custom fields are read-only on issues.
