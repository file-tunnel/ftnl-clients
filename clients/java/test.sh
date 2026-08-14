#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

classes_dir="${TMPDIR:-/tmp}/ftnl-java-test-classes"
mkdir -p "$classes_dir"
find src -name '*.java' -exec javac -Werror -d "$classes_dir" {} +
