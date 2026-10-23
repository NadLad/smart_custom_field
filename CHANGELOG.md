# Changelog

## 0.1.0 — 2026-10-23

Initial release, parity with `computed_custom_field` on Redmine 7.0.x.

- Adds `formula` and `is_computed` columns to `custom_fields`; both migrations
  are skipped when the columns already exist, so an existing
  `computed_custom_field` installation is taken over without data migration.
- Admin UI: computed checkbox, formula textarea, list of the fields a formula
  can reference, double-click (or Enter) to insert a `cfs[<id>]` placeholder.
- Computed values are evaluated in a `before_validation` callback and persisted
  with the customized object, for every model declaring
  `acts_as_customizable`.
- `cfs[<id>]` values are cast to their custom field format; an empty numeric
  field is exposed as `0`.
- The formula is validated on save: blank formula, syntax error, unknown method
  and references to a custom field of another type are rejected.
- A formula raising at runtime blocks the save and reports the error on the
  object.
- Computed fields are read-only on issues: excluded from the form and from
  mass assignment.
- English and French locales.
- Docker test harness (`bin/test.sh`) against `redmine:7.0.2`.
