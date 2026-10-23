#!/bin/sh
# Run the plugin test suite inside the dedicated Redmine 7.0.2 test image.
#
# Nothing is installed on the host: the image ships Ruby, the gems Redmine's
# test_helper needs (mocha, net-ldap) and the core test schema. Only the plugin
# migrations have to run on every invocation, since the image cannot know about
# them at build time.
#
# Usage:  docker/run-tests.sh [extra rake options]
set -eu

PLUGIN=smart_custom_field
IMAGE=${IMAGE:-smart_custom_field-test}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

docker run --rm --user root \
  -v "$ROOT:/usr/src/redmine/plugins/$PLUGIN" \
  -w /usr/src/redmine \
  "$IMAGE" \
  sh -c "RAILS_ENV=test bundle exec rake redmine:plugins:migrate NAME=$PLUGIN >/dev/null 2>&1
         RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=$PLUGIN $*"
