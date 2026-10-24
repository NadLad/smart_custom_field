# Changelog

## 0.3.0 — 2026-10-23

Five evolutions, all of them a strict superset of `computed_custom_field`: no
existing formula changes meaning, and no stored value is rewritten without
being asked for. Two behaviour changes are deliberate and documented below —
read-only enforcement now covers every customizable model, and aggregations
fail loudly past their caps.

### Version bump

`SmartCustomField::VERSION` is now `0.3.0`. One migration is added
(`003_add_smart_custom_field_computations`); it creates a new digest table and
touches no existing column.

### Recompute every stored value

`rake smart_custom_field:recompute_all` walks every record of every
customizable model, recomputes each computed field and rewrites the stored
value where it differs. Dry run unless `APPLY=true`; `BATCH_SIZE` (default
500) and `USER_ID` are optional. It writes values only — `updated_on` is
untouched and no journal entry is created, so recomputing a thousand issues
does not rewrite their history or notify anybody. A field whose formula raises
is reported and skipped rather than aborting the run, and the task exits
non-zero at the end. This is the task to run after importing formulas from
another instance, after a far-reaching formula change, or after taking over
values that were never computed.

### Cycle detection

A formula that reads a field which itself reads the first one is now refused on
save: `FormulaCycle.detect` walks the graph of computed fields of the same
type through `Evaluator.custom_field_ids` and returns the path
(`1 -> 3 -> 2 -> 1`), which the validator reports as `error_formula_cycle` with
the path in the message. A cycle that is *already stored* is allowed through
with a log warning, so it can be repaired from the admin instead of becoming
unsavable.

### Read-only on every customizable model

Computed fields were read-only on issues only; on a project, user, time entry,
version, group, enumeration or document the field was shown as an input and
whatever was typed was replaced on save. That is now uniform: the field renders
as text on all eight models and its id is dropped from anything assigned from
the outside, so a crafted `POST` cannot store a value the next save would fight
with. The only writer left is the computation itself, which opens a scoped
thread-local window around its own assignment
(`FormulaComputation.writing { ... }`). A failed formula no longer lets a
submitted value through, and a field that has never been computed shows
*Computed when the record is saved* instead of an empty input.

### Skip the evaluation when the inputs did not change

Every computed field stores a digest of the last evaluation in
`smart_custom_field_computations`: the formula itself plus every referenced
input, plus all of the record's own attributes except the timestamps and the
lock version. On save, an unchanged digest skips the evaluation and the write
entirely. A formula that reads a related object (`parent`, `assigned_to`, the
project) or a volatile value (`Date.today`, `Time.now`, `rand`) is detected by
the static analyzer and gets **no** digest, so it recomputes on every save
instead of serving a stale value. When in doubt the plugin recomputes.

### Aggregations

Five helpers on every customizable model: `cf_sum(collection, id)`,
`cf_avg(collection, id)`, `cf_min(collection, id)`, `cf_max(collection, id)`
and `subtree(issue)` (the issues below an issue, itself excluded) — so
`cf_sum(children, 7)` and `cf_avg(subtree, 7)` need no loop in the formula. An
unset value is ignored rather than counted as `0`, so an average over three
issues where two filled the field divides by two. A collection past
`MAX_COLLECTION` (1000, detected with `limit(cap + 1)` so the relation is never
loaded) or a subtree past `MAX_DEPTH` (5 levels) raises `AggregationError` with
an explicit message instead of silently truncating. An empty collection totals
to `0`; `cf_avg` / `cf_min` / `cf_max` return `nil` for it.

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
