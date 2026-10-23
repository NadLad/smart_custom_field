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
values, read-only, idempotent patching) and the admin form.

## Compatibility with computed_custom_field

| Aspect | Status |
|---|---|
| Columns (`formula`, `is_computed`) | identical |
| Formula syntax (`cfs[<id>]`, Ruby, `self`) | identical |
| Admin form (checkbox, textarea, field list, double-click) | identical |
| Formula validation on save | added |
| Computed fields read-only on issues | added |

## License

MIT — see [MIT-LICENSE](MIT-LICENSE).
