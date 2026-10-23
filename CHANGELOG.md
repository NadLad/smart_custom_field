# Changelog

## 0.2.0 — 2026-10-23

Six evolutions, all of them a strict superset of `computed_custom_field`: no
existing formula changes meaning, no stored value is rewritten.

### Export / import of formulas

`rake smart_custom_field:export[file]` dumps every computed field (id, name,
type, format, formula) to JSON; `rake smart_custom_field:import[file]` compares
that file with the current state and only writes when `APPLY=true`. The import
rewrites the `formula` column and nothing else — it cannot create a custom
field, cannot touch a stored value, and never deletes anything.

### Static analysis of stored formulas

`rake smart_custom_field:check` parses every formula with Ripper and reports
what the save-time validator cannot see: unknown methods on a resolved
receiver, syntax errors in older formulas, `cfs[...]` ids that no longer match
a field, and `User.current` (a value that depends on who saved last). Warn
only — it never edits a formula and never fails a build.

### Admin preview

The custom field form gained a preview panel: enter the id of a real issue or
project and the formula is evaluated against it, showing the result, the
stored value, the inputs it read and the static warnings. Nothing is written.
Administrator only.

### Explain a saved value

`GET /smart_custom_field/explain` answers *why is this field 15?* for a saved
field: same breakdown as the preview, with the formula taken from the field
instead of the request. Read only, administrator only.

### Cross-object helpers

`cf(object, id)` and a public `cfs` on every customizable model
(`parent&.cfs[5]`, `assigned_to.cfs[3]`), cast exactly like `cfs` so the same
field is never a String in one formula and an Integer in another. Values of a
related object are cached for the duration of one computation, then dropped.
No existing Redmine method is shadowed — the suite asserts it on all eight
customizable models.

### Condition builder

The admin form builds a formula from *field, operator, value* rows joined by
and/or, and inserts the generated expression at the cursor. One-way generator:
the textarea stays the source of truth and the rows are never read back from
it. Operators and quoting follow the field format.

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
