# Smart Custom Field

Computed custom fields for Redmine 7.0.x.

A computed custom field takes no user input: its value is calculated by a
formula evaluated in the context of the customized object (issue, project,
user, time entry, version, group, enumeration, document).

This plugin is a rewrite of
[computed_custom_field](https://github.com/annikoff/redmine_plugin_computed_custom_field)
for Redmine 7.0. It keeps the same columns (`formula`, `is_computed`) and the
same formula syntax, so it can replace the original plugin without migrating
data.

## Requirements

- Redmine 7.0.x (Rails 8.1, Ruby >= 3.2)
- No extra gem.

## Installation

```sh
cd /path/to/redmine/plugins
git clone <repository-url> smart_custom_field
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Restart Redmine.

## Usage

1. Administration → Custom fields → new field.
2. Tick **Computed**, write the formula.
3. Double-click a field in the list to insert its `cfs[<id>]` placeholder.

```ruby
cfs[1] * 2 + cfs[2]
```

The formula is Ruby evaluated with `self` bound to the customized object, so
model attributes are available too:

```ruby
(self.estimated_hours || 0) * 2
```

## Documentation

Full reference, examples and limitations: see the plugin wiki once published.

## License

MIT — see [MIT-LICENSE](MIT-LICENSE).
