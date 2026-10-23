# Smart Custom Field

[![Redmine](https://img.shields.io/badge/Redmine-7.0.x-b32024?style=flat-square)](https://www.redmine.org)
[![Ruby](https://img.shields.io/badge/Ruby-%E2%89%A5%203.2-CC342D?style=flat-square)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](MIT-LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-informational?style=flat-square)](CHANGELOG.md)

**Computed custom fields for Redmine 7.0.x.** A computed field takes no user
input: its value is calculated by a formula evaluated in the context of the
customized object — issue, project, user, time entry, version, group,
enumeration, document — and recomputed on every save.

This is a rewrite of
[computed_custom_field](https://www.redmine.org/plugins/computed_custom_field)
that keeps its data contract exactly: same columns (`formula`, `is_computed`),
same `cfs[<id>]` syntax, same serialization of the stored value. An existing
installation switches over without migrating a single row. On top of that
parity it adds the tooling the original never had — validation, static
analysis, preview, explain, export/import — plus cross-object helpers and a
condition builder.

## Table of contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Creating a computed field](#creating-a-computed-field)
  - [Formula syntax](#formula-syntax)
  - [Cross-object helpers](#cross-object-helpers)
  - [Condition builder](#condition-builder)
  - [Preview and explain](#preview-and-explain)
  - [Validation](#validation)
  - [Read-only](#read-only)
- [Formula cookbook](#formula-cookbook)
- [Maintenance](#maintenance)
- [How it works](#how-it-works)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Upgrading and uninstalling](#upgrading-and-uninstalling)
- [Development](#development)
- [Switching from computed_custom_field](#switching-from-computed_custom_field)
- [Roadmap](#roadmap)
- [License](#license)

## Quick start

```sh
cd /path/to/redmine/plugins
git clone https://github.com/NadLad/smart_custom_field.git smart_custom_field

cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
# restart Redmine
```

Then **Administration → Custom fields → New**, tick **Computed**, and write a
formula such as:

```ruby
(self.estimated_hours || 0) * cfs[12]
```

The field now recalculates itself every time an issue is saved. It never asks
the user for a value.

## Requirements

| Requirement | Version |
|---|---|
| Redmine | 7.0.x (Rails 8.1) |
| Ruby | >= 3.2 (the official `redmine:7.0.2` image ships 4.0.8) |
| Database | any supported by Redmine |
| Extra gem | none |

## Installation

```sh
cd /path/to/redmine/plugins
git clone https://github.com/NadLad/smart_custom_field.git smart_custom_field
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Restart Redmine. The two migrations add `formula` and `is_computed` to
`custom_fields`, and each one is skipped when its column already exists — so
installing this plugin on a database previously managed by
`computed_custom_field` keeps every existing formula, without any data
migration.

**Do not run both plugins at once.** They patch the same classes
(`CustomField`, `Customizable`) and the inclusion order would decide which one
computes. [Switching](#switching-from-computed_custom_field) is a two-step
operation.

## Usage

### Creating a computed field

1. Administration → Custom fields → new field, pick the object it belongs to.
2. Tick **Computed**. The flag can only be set at creation: flipping it later
   would silently reinterpret values already stored.
3. Write the formula. The list below the textarea shows every custom field the
   formula may reference; double-click one (or press Enter on it) to insert its
   `cfs[<id>]` placeholder at the cursor.

### Formula syntax

The formula is Ruby code evaluated with `self` bound to the customized object,
so both custom fields and model attributes are available:

| Formula | Result |
|---|---|
| `cfs[1] * 2 + cfs[2]` | arithmetic on two integer custom fields |
| `(self.estimated_hours \|\| 0) * 2` | model attribute |
| `cfs[3] > 2 ? %w[low high] : %w[low]` | multiple values (list format) |
| `"#{subject} (#{cfs[4]})"` | string interpolation |

`cfs[<id>]` holds the value of another custom field, already cast to its
format: an integer field gives an Integer, a date field a Date, a user field a
User. A numeric field left empty is exposed as `0`, so arithmetic formulas do
not blow up on a partially filled object. A field that is not available on the
object — filtered out by tracker or project — is simply absent, so `cfs[<id>]`
is `nil` there; use `cfs[<id>] || 0` if the field is optional.

The result is cast to the format of the field being computed:

| Target format | Stored value |
|---|---|
| `int` | `to_i` of the result |
| `float` | the result, as a decimal string |
| `bool` | `1` only for a literal `true`, `0` for anything else |
| `list` / `string` / `text` | the result, as a string |
| `date` / `datetime` | the result, as a date or time string |
| `user` | the id of the User the result points to |
| multiple values | an array produces one value per element |

### Cross-object helpers

`cfs` only holds the custom fields of the object being computed. To read a
value carried by a related object, use `cf` or call `cfs` on it:

| Formula | Result |
|---|---|
| `cf(project, 12) * 2` | value of custom field 12 of the issue's project |
| `parent&.cfs[5]` | value of custom field 5 of the parent issue, `nil` if none |
| `assigned_to.cfs[3]` | value of custom field 3 of the assignee |

Both go through the same cast as `cfs`, so the same field is never a String in
one formula and an Integer in another. The values of a related object are
cached for the duration of one computation and the cache is dropped after each
save. `cfs` is public on all eight customizable models; no existing Redmine
method is shadowed (the suite asserts it model by model).

### Condition builder

Below the textarea, the condition builder generates an expression from rows of
*field, operator, value* joined by **and** / **or**, and inserts it at the
cursor:

```
cfs[12] > 5 && cfs[13] == 'open'
```

It is a **one-way generator**: the formula textarea stays the source of truth
and the rows are never read back from it. Editing the formula by hand is
therefore always safe — it simply stops matching what the rows describe.
Operators and quoting follow the format of the field: a boolean only knows
`==` and `!=` and compares to `true`/`false`, a date compares to
`Date.parse('2026-01-01')`, a text field is single-quoted with its apostrophes
escaped, and an empty numeric input becomes `0` rather than a dangling
comparison.

### Preview and explain

The admin form carries a **preview** panel. Give it the id of an existing
issue, project or other customizable object and it evaluates the formula
against that object — without saving anything — showing the result, the value
that would be stored, every custom field the formula actually read, and the
static warnings.

`GET /smart_custom_field/explain?custom_field_id=<id>&object_id=<id>` answers
the other question, the one asked months later in front of a filled issue —
*why is this field 15?* — for a **saved** field, taking the formula from the
field instead of the request. Same breakdown, same read-only guarantee:

```json
{
  "ok": true,
  "formula": "(self.estimated_hours || 0) * cfs[12]",
  "object": { "type": "Issue", "id": 42 },
  "inputs": [
    { "id": 12, "name": "Hourly rate", "format": "float", "raw": "85.0", "cast": "85.0" }
  ],
  "warnings": [],
  "result": "1700.0",
  "result_class": "Float",
  "cast_value": "1700.0"
}
```

Both endpoints are administrator-only: a formula runs arbitrary Ruby in the
context of the object, the same trust level as the custom field form they
belong to. The preview accepts any object type from the customizable list; the
explain endpoint derives the type from the field itself.

### Validation

Saving a computed field checks its formula: blank formulas, syntax errors,
method typos and `cfs[...]` references to a custom field of another type are
rejected with a message on the formula. Errors caused by a `nil` attribute are
ignored, since the probe runs on a blank object where every optional attribute
is empty.

At runtime, a formula that raises while an object is saved blocks the save and
adds the error to the object:

```
Error while computing custom field Total: undefined method 'foo' for nil
```

The save-time check is deliberately lenient — it cannot know which methods a
third-party plugin adds. For everything it cannot see, use
[`rake smart_custom_field:check`](#static-analysis).

### Read-only

On issues, computed fields are never editable: they are excluded from the
issue form and from mass assignment, so a submitted value cannot silently
override the computed one. On the other customizable models (project, user,
time entry, version, group, enumeration, document) the field is still shown in
the form, but whatever is typed is replaced by the computed value on save.

## Formula cookbook

Recipes that work as-is once you replace the custom field ids. Pick the target
format on the right.

| Goal | Formula | Format |
|---|---|---|
| Hourly cost of an issue | `(self.estimated_hours \|\| 0) * cfs[12]` | float |
| Budget exceeded | `(self.estimated_hours \|\| 0) * cfs[12] > cfs[13]` | bool |
| Severity label from a score | `cfs[14] >= 8 ? 'critical' : 'normal'` | list |
| Extra labels for bugs | `%w[bug].include?(tracker.name.downcase) ? %w[bug critical] : %w[bug]` | list (multiple) |
| Tracker and project path | `"#{tracker.name} / #{project.name}"` | string |
| Calendar days between two dates | `(due_date - start_date).to_i` | int |
| Share of the project budget | `cf(project, 12) > 0 ? ((self.estimated_hours \|\| 0) * cfs[13] * 100.0 / cf(project, 12)).round(1) : 0` | float |
| Assignee name | `assigned_to&.name` | string |
| Inherit the parent's field | `cfs[5] \|\| parent&.cfs[5]` | string |
| Overdue by more than 3 days | `due_date.present? && (due_date - Date.today).to_i < -3` | bool |

A list field only stores a string that matches one of its allowed values, so
a formula producing a label must produce exactly one of them; an array on a
multiple-values field produces one value per element.

Two caveats worth knowing before writing formulas:

- **The value is computed on save, not on read.** `Date.today`, `Time.now` and
  anything else time-dependent freeze at the moment of the last save. That is
  fine for a deadline label, misleading for a live countdown.
- **`User.current` makes a stored value depend on who saved last.** Two people
  saving the same issue get different values for the same data. The static
  analyzer flags it.

## Maintenance

Three rake tasks ship with the plugin, all run from the Redmine root.

### Export and import formulas

```sh
# Dump every computed field to JSON (id, name, type, format, formula)
bundle exec rake smart_custom_field:export[formulas.json]

# Show what an import would change, without writing anything
bundle exec rake smart_custom_field:import[formulas.json]

# Actually apply it
APPLY=true bundle exec rake smart_custom_field:import[formulas.json]
```

The import is a **dry run unless `APPLY=true`**. It matches fields by id, then
by name and type, and only ever rewrites the `formula` column: it cannot create
a custom field and cannot touch a stored value. Fields present on one side only
are reported, not deleted. The file carries a `format_version`, so a future
change of the format is refused rather than misread.

This is the migration path between environments: export from the old Redmine,
import on the new one, and the diff tells you exactly which formulas changed.
It is also your backup before an uninstall.

### Static analysis

```sh
bundle exec rake smart_custom_field:check
```

Parses every stored formula with Ripper and reports what the save-time
validator cannot see: a method that does not exist on the receiver, a syntax
error in a formula that predates the validator, a `cfs[...]` id that no longer
matches a custom field of the same type, and `User.current` (a formula reading
the current user makes the stored value depend on *who saved last*).

The task **only warns**: it never edits a formula and never fails a build. A
formula calling a method added by another plugin is reported as unknown and may
be perfectly valid, which is exactly why the save-time validator stays lenient
about it too. The analyzer parses, it never evaluates — running it on a
production database does not execute any formula.

## How it works

Evaluation happens in a `before_validation` callback on every model declaring
`acts_as_customizable`, so the computed value is part of the object being
saved, not a follow-up write:

```
save
 └─ before_validation
     ├─ Evaluator.values_for(object)        # cfs: cast values, keyed by field id
     ├─ for each computed field (in position order)
     │   ├─ Evaluator.evaluate(formula, object, cfs)   # eval, self = object
     │   └─ Evaluator.cast(field, result)              # → custom_values.value
     └─ a formula that raises aborts the save with an error on the object
```

The preview and the explain endpoint go through the same `Preview` builder, so
what an administrator sees in the admin form is what a save would store.

| Path | Role |
|---|---|
| `init.rb` | registers the plugin, applies every patch |
| `lib/smart_custom_field/patches.rb` | patch registry, idempotent across code reloads |
| `lib/smart_custom_field/patches/customizable_patch.rb` | computes values on save, exposes `cfs` |
| `lib/smart_custom_field/patches/custom_field_patch.rb` | validates the formula, freezes `is_computed` |
| `lib/smart_custom_field/patches/issue_patch.rb` | read-only on issues |
| `lib/smart_custom_field/patches/custom_fields_helper_patch.rb` | admin form, field list, builder |
| `lib/smart_custom_field/evaluator.rb` | `eval`, `cfs` casting, result casting |
| `lib/smart_custom_field/formula_validator.rb` | save-time checks |
| `lib/smart_custom_field/static_analyzer.rb` | Ripper analysis for `rake check` |
| `lib/smart_custom_field/formula_export.rb` | JSON dump, diff, apply |
| `lib/smart_custom_field/formula_helpers.rb` | `cf(object, id)` and `cfs` on related objects |
| `lib/smart_custom_field/preview.rb` | payload shared by preview and explain |
| `app/controllers/smart_custom_field/previews_controller.rb` | the two admin endpoints |
| `app/assets/javascripts/smart_custom_field_formula_builder.js` | condition builder |

Keeping evaluation in one module is deliberate: replacing `eval` with a
restricted interpreter later means touching `Evaluator` and nothing else.

## Security

- **Formulas are Ruby code.** Evaluation uses `eval` with `self` bound to the
  customized object. Only administrators can create custom fields, so this is
  the same trust level as installing a plugin — but a formula can read anything
  the application can read. A sandboxed interpreter is not implemented; it is
  on the [roadmap](#roadmap).
- **Both endpoints are admin-only** and both are read-only. They cannot write a
  custom value, and the preview only instantiates types from the closed
  customizable list, never a constant taken from the request.
- **The import task writes one column.** It cannot create a field, delete a
  field, or touch `custom_values`.
- **The static analyzer never executes a formula.** It parses source with
  Ripper, so it is safe to run against production data.
- **Nothing runs on the host** for development: the whole test suite is in
  Docker (see [Development](#development)).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `cfs[42]` is `nil` in the preview although field 42 exists | the field is not available on that object (filtered by tracker or project) | enable the field for that tracker/project, or write `cfs[42] \|\| 0` |
| Saving fails with `undefined method ... for nil` | the formula walks an association that is empty on this object | use `&.`, `\|\| 0`, or guard with `present?` |
| The value does not change when an input changes | the input is another *computed* field: chained fields read the value stored by the previous save | save twice, or avoid chaining computed fields |
| The value is stale although nothing was edited | the formula reads `Date.today` / `Time.now`; the value freezes at the last save | expect it, or compute from stored dates instead |
| Preview returns `403` | the account is not an administrator | use an admin account |
| Preview or explain returns `404` | the object id does not exist, the field is not computed, or the field type has no customizable model | check the id and the field |
| The admin form shows no preview panel | the custom field's model is not in the customizable list | the panel only exists where a value can be computed |
| `rake check` flags a method that works | the method comes from another plugin | ignore it; the task is advisory by design |
| A computed field is editable on a project/user form | read-only enforcement is issue-only | expected — the typed value is overwritten on save |
| The plugin does nothing after an upgrade | the patch was not reapplied | restart Redmine; `init.rb` runs on `to_prepare` |

## Upgrading and uninstalling

**Upgrade:**

```sh
cd /path/to/redmine/plugins/smart_custom_field
git pull
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
# restart Redmine
```

0.2.0 adds no migration and changes no stored value: every formula written for
0.1.0 or for `computed_custom_field` keeps its meaning.

**Uninstall:**

```sh
# 1. Keep the formulas — the uninstall migration drops the columns
bundle exec rake smart_custom_field:export[formulas.json]

# 2. Roll the plugin migrations back (drops formula and is_computed)
bundle exec rake redmine:plugins:migrate NAME=smart_custom_field VERSION=0

# 3. Remove plugins/smart_custom_field and restart Redmine
```

Step 2 is destructive: `formula` and `is_computed` are dropped, and with them
every formula. The computed *values* already stored in `custom_values` are
untouched — they simply stop being recalculated.

## Development

Everything runs in Docker, nothing is installed on the host. The test image is
built from the official `redmine:7.0.2` image (Ruby 4.0.8, Rails 8.1.4) plus
the gems Redmine's `test_helper` needs:

```sh
bin/test.sh build   # build the test image
bin/test.sh         # run the plugin test suite (default)
bin/test.sh boot    # boot Redmine in test env and list the loaded plugins
bin/test.sh shell   # shell in the container, plugin mounted
```

`bin/test.sh` exits non-zero on failure, so it works as a CI step. To run a
single file:

```sh
docker run --rm --user root \
  -v "$PWD:/usr/src/redmine/plugins/smart_custom_field" \
  -w /usr/src/redmine smart_custom_field-test \
  sh -c 'RAILS_ENV=test bundle exec rake redmine:plugins:migrate NAME=smart_custom_field >/dev/null 2>&1;
         RAILS_ENV=test bundle exec rails test plugins/smart_custom_field/test/functional/preview_test.rb'
```

The suite (105 runs, 313 assertions) covers the evaluator, the formula
validator, the model patches (computed values, read-only, idempotent patching),
the cross-object helpers, the export/import round trip, the static analyzer,
the condition builder expression generator, the admin form and the two admin
endpoints.

## Switching from computed_custom_field

The data contract is identical, so the switch is about removing one plugin
before installing the other — never running both.

1. **Back up the database.** Both plugins write the same columns.
2. **Remove `plugins/computed_custom_field`** and restart Redmine. Do *not* run
   `rake redmine:plugins:migrate NAME=computed_custom_field VERSION=0`: its
   uninstall migration drops `formula` and `is_computed`, and with them every
   formula.
3. **Install `smart_custom_field`** and migrate. Both migrations detect the
   existing columns and skip themselves, so the formulas stay in place.
4. **Audit** with `bundle exec rake smart_custom_field:check`.
5. **Spot-check** a few fields in the admin preview before trusting a mass
   save.

| Aspect | Status |
|---|---|
| Columns (`formula`, `is_computed`) | identical |
| Formula syntax (`cfs[<id>]`, Ruby, `self`) | identical |
| Admin form (checkbox, textarea, field list, double-click) | identical |
| Formula validation on save | added |
| Computed fields read-only on issues | added |
| `cf(object, id)` / `object.cfs` | added, strict superset |
| Condition builder, preview, explain | added, new UI only |
| `export` / `import` / `check` rake tasks | added, read-only on data |

Every addition is a **strict superset**: no formula written for
`computed_custom_field` changes meaning, and nothing here rewrites a stored
value on its own.

## Roadmap

The evolutions beyond parity are grouped in three risk zones and shipped zone
by zone. **0.2.0 is zone A** — the six changes with zero impact on stored
data:

| Evolution | Surface |
|---|---|
| Export / import JSON | `rake smart_custom_field:export` / `:import` |
| Static analysis | `rake smart_custom_field:check` |
| Admin preview | form panel + `POST /smart_custom_field/preview` |
| Explain a saved value | `GET /smart_custom_field/explain` |
| Cross-object helpers | `cf(object, id)`, `cfs` on related objects |
| Condition builder | admin form, one-way generator |

Not delivered yet, by design: cycle detection, backfill, uniform read-only,
aggregations, dependency-driven recompute, topological ordering, a sandboxed
interpreter, and named formula libraries. Each of them either changes the
result of an existing formula or writes stored values, so each ships behind an
explicit opt-in.

## License

MIT — see [MIT-LICENSE](MIT-LICENSE).


