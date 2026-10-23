#!/bin/sh
# Docker harness for the smart_custom_field plugin.
#
# Nothing runs on the host: every command executes in the test image built
# from docker/Dockerfile.test, which is the official redmine:7.0.2 image with
# Ruby, the gems Redmine's test_helper needs and the core test schema.
#
# Usage: bin/test.sh [command]
#
#   test   (default) migrate the plugin and run its test suite
#   boot   boot Redmine in the test environment and list the loaded plugins
#   build  rebuild the test image
#   shell  open a shell in the image with the plugin mounted
set -eu

PLUGIN=smart_custom_field
IMAGE=${IMAGE:-smart_custom_field-test}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMMAND=${1:-test}

run() {
  docker run --rm --user root \
    -v "$ROOT:/usr/src/redmine/plugins/$PLUGIN" \
    -w /usr/src/redmine \
    "$IMAGE" "$@"
}

case "$COMMAND" in
  test)
    exec "$ROOT/docker/run-tests.sh"
    ;;
  boot)
    run sh -c 'RAILS_ENV=test bundle exec ruby -e "require %q(./config/environment); Redmine::Plugin.all.each { |plugin| puts [plugin.id, plugin.name, plugin.version].join(%q( | )) }"'
    ;;
  build)
    docker build -f "$ROOT/docker/Dockerfile.test" -t "$IMAGE" "$ROOT"
    ;;
  shell)
    docker run --rm -it --user root \
      -v "$ROOT:/usr/src/redmine/plugins/$PLUGIN" \
      -w /usr/src/redmine \
      "$IMAGE" sh
    ;;
  *)
    echo "Unknown command: $COMMAND (expected test, boot, build or shell)" >&2
    exit 2
    ;;
esac
