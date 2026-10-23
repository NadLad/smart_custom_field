# Smart Custom Field

Computed custom fields for Redmine 7.0.x.

A computed custom field takes no user input: its value is calculated by a
formula evaluated in the context of the customized object (issue, project,
user, time entry, version, group, enumeration, document) and recomputed on
every save.

This plugin is a rewrite of
[computed_custom_field](https://www.redmine.org/plugins/computed_custom_field)
for Redmine 7.0. It keeps the same columns (`formula`, `is_computed`) and the
same `cfs[<id>]` formula syntax, so it can take over an existing installation
without migrating any data.

## Requirements

| Requirement | Version |
|---|---|
| Redmine | 7.0.x (Rails 8.1) |
| Ruby | >= 3.2 (the official 7.0.2 image ships 4.0) |
| Database | any supported by Redmine |
| Extra gem | none |

## Installation

```sh
cd /path/to/redmine/plugins
git clone <repository-url> smart_custom_field
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Restart Redmine. The migrations add `formula` and `is_computed` to
`custom_fields`; both are skipped when the columns already exist, so
uninstalling `computed_custom_field` and installing this plugin on the same
database keeps every existing formula.

## Usage

1. Administration → Custom fields → new field.
2. Tick **Computed** (only possible at creation time).
3. Write the formula, or double-click a field in the list below the textarea
   to insert its `cfs[<id>]` placeholder at the cursor.

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
not blow up on a partially filled object.

The result is cast to the format of the field being computed: an `int` field
truncates to an integer, a `bool` field stores `1` for a truthy result and `0`
otherwise, a `list` field stores the string, and an array produces one value
per element for a multiple field.

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
cached for the duration of one computation and the cache is dropped after
each save.

### Condition builder

Below the textarea, the condition builder generates an expression from rows of
*field, operator, value* joined by **ET** (and) or **OU** (or), and inserts it
at the cursor:

```
cfs[12] > 5 && cfs[13] == 'open'
```

It is a **one-way generator**: the formula textarea stays the source of truth
and the rows are never read back from it. Editing the formula by hand is
therefore always safe, it simply stops matching what the rows describe.
Operators and quoting follow the format of the field: a boolean only knows
`==` and `!=` and compares to `true`/`false`, a date compares to
`Date.parse('2026-01-01')`, a text field is single-quoted with its apostrophes
escaped, and an empty numeric input becomes `0` rather than a dangling
comparison.

### Preview and explain

The admin form carries a **preview** panel: give it the id of an existing
issue, project or other customizable object and it evaluates the formula
against that object, showing the result, the stored value, every custom field
the formula read and the static warnings. Nothing is written.

`GET /smart_custom_field/explain?custom_field_id=<id>&object_id=<id>` answers
the other question, the one asked months later in front of a filled issue —
*why is this field 15?* — for a **saved** field, taking the formula from the
field instead of the request. Same breakdown, same read-only guarantee.

Both endpoints are administrator-only: a formula runs arbitrary Ruby in the
context of the object, the same trust level as the custom field form they
belong to.

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

### Read-only

On issues, computed fields are never editable: they are excluded from the
issue form and from mass assignment, so a submitted value cannot silently
override the computed one. On the other customizable models (project, user,
time entry, version, group, enumeration, document) the field is still shown in
the form, but whatever is typed is replaced by the computed value on save.

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
about it too.

## Known limitations

- **Formulas are Ruby code.** Evaluation uses `eval` in the context of the
  customized object. Only administrators can create custom fields, so this is
  the same trust level as a Redmine plugin, but a formula can read anything the
  application can read. A sandboxed interpreter is not implemented.
- **Evaluation order.** Computed fields are evaluated in the order the object
  exposes them (custom field position). A computed field that references
  another computed field reads the value stored by the previous save, not the
  one being computed.
- **No value history.** Each save overwrites the previous value; the journal
  records the change like any other custom field value.
- **Issue-only read-only enforcement** (see above).

## Development

Everything runs in Docker, nothing is installed on the host. The test image is
built from the official `redmine:7.0.2` image plus the gems Redmine's
`test_helper` needs:

```sh
bin/test.sh build   # build the test image
bin/test.sh         # run the plugin test suite (default)
bin/test.sh boot    # boot Redmine in test env and list the loaded plugins
bin/test.sh shell   # shell in the container, plugin mounted
```

`bin/test.sh` exits non-zero on failure, so it works as a CI step. The suite
covers the evaluator, the formula validator, the model patches (computed
values, read-only, idempotent patching), the cross-object helpers, the
export/import round trip, the static analyzer, the admin form (preview panel,
condition builder) and the two admin endpoints.

## Compatibility with computed_custom_field

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

## License

MIT — see [MIT-LICENSE](MIT-LICENSE).
