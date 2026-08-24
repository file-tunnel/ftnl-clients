#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

classes_dir="${TMPDIR:-/tmp}/ftnl-java-test-classes"
mkdir -p "$classes_dir"
find "$classes_dir" -type f -delete
find src -name '*.java' -print0 \
  | xargs -0 javac -Werror --release 17 --add-modules jdk.httpserver -d "$classes_dir"
java --add-modules jdk.httpserver -cp "$classes_dir" io.filetunnel.client.FtnlClientTest
