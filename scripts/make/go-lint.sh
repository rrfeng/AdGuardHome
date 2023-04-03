#!/bin/sh

# This comment is used to simplify checking local copies of the script.  Bump
# this number every time a significant change is made to this script.
#
# AdGuard-Project-Version: 3

verbose="${VERBOSE:-0}"
readonly verbose

if [ "$verbose" -gt '0' ]
then
	set -x
fi

# Set $EXIT_ON_ERROR to zero to see all errors.
if [ "${EXIT_ON_ERROR:-1}" -eq '0' ]
then
	set +e
else
	set -e
fi

set -f -u



# Source the common helpers, including not_found and run_linter.
. ./scripts/make/helper.sh



# Warnings

go_version="$( "${GO:-go}" version )"
readonly go_version

go_min_version='go1.19.7'
go_version_msg="
warning: your go version (${go_version}) is different from the recommended minimal one (${go_min_version}).
if you have the version installed, please set the GO environment variable.
for example:

	export GO='${go_min_version}'
"
readonly go_min_version go_version_msg

case "$go_version"
in
('go version'*"$go_min_version"*)
	# Go on.
	;;
(*)
	echo "$go_version_msg" 1>&2
	;;
esac



# Simple analyzers

# blocklist_imports is a simple check against unwanted packages.  The following
# packages are banned:
#
#   *  Packages errors and log are replaced by our own packages in the
#      github.com/AdguardTeam/golibs module.
#
#   *  Package io/ioutil is soft-deprecated.
#
#   *  Package reflect is often an overkill, and for deep comparisons there are
#      much better functions in module github.com/google/go-cmp.  Which is
#      already our indirect dependency and which may or may not enter the stdlib
#      at some point.
#
#      See https://github.com/golang/go/issues/45200.
#
#   *  Package sort is replaced by golang.org/x/exp/slices.
#
#   *  Package unsafe is… unsafe.
#
#   *  Package golang.org/x/net/context has been moved into stdlib.
#
blocklist_imports() {
	git grep\
		-e '[[:space:]]"errors"$'\
		-e '[[:space:]]"io/ioutil"$'\
		-e '[[:space:]]"log"$'\
		-e '[[:space:]]"reflect"$'\
		-e '[[:space:]]"sort"$'\
		-e '[[:space:]]"unsafe"$'\
		-e '[[:space:]]"golang.org/x/net/context"$'\
		-n\
		-- '*.go'\
		| sed -e 's/^\([^[:space:]]\+\)\(.*\)$/\1 blocked import:\2/'\
		|| exit 0
}

# method_const is a simple check against the usage of some raw strings and
# numbers where one should use named constants.
method_const() {
	git grep -F\
		-e '"DELETE"'\
		-e '"GET"'\
		-e '"POST"'\
		-e '"PUT"'\
		-n\
		-- '*.go'\
		| sed -e 's/^\([^[:space:]]\+\)\(.*\)$/\1 http method literal:\2/'\
		|| exit 0
}

# underscores is a simple check against Go filenames with underscores.  Add new
# build tags and OS as you go.  The main goal of this check is to discourage the
# use of filenames like client_manager.go.
underscores() {
	underscore_files="$(
		git ls-files '*_*.go'\
			| grep -F\
			-e '_big.go'\
			-e '_bsd.go'\
			-e '_darwin.go'\
			-e '_freebsd.go'\
			-e '_linux.go'\
			-e '_little.go'\
			-e '_next.go'\
			-e '_openbsd.go'\
			-e '_others.go'\
			-e '_test.go'\
			-e '_unix.go'\
			-e '_windows.go' \
			-v\
			| sed -e 's/./\t\0/'
	)"
	readonly underscore_files

	if [ "$underscore_files" != '' ]
	then
		echo 'found file names with underscores:'
		echo "$underscore_files"
	fi
}

# TODO(a.garipov): Add an analyzer to look for `fallthrough`, `goto`, and `new`?



# Checks

run_linter -e blocklist_imports

run_linter -e method_const

run_linter -e underscores

run_linter -e gofumpt --extra -e -l .

# TODO(a.garipov): golint is deprecated, find a suitable replacement.

run_linter "$GO" vet ./...

run_linter govulncheck ./...

# Apply more lax standards to the code we haven't properly refactored yet.
run_linter gocyclo --over 13\
	./internal/dhcpd\
	./internal/home/\
	./internal/querylog/\
	;

# Apply the normal standards to new or somewhat refactored code.
run_linter gocyclo --over 10\
	./internal/aghio/\
	./internal/aghnet/\
	./internal/aghos/\
	./internal/aghtest/\
	./internal/dnsforward/\
	./internal/filtering/\
	./internal/stats/\
	./internal/tools/\
	./internal/updater/\
	./internal/next/\
	./internal/version/\
	./scripts/blocked-services/\
	./scripts/vetted-filters/\
	./scripts/translations/\
	./main.go\
	;

run_linter ineffassign ./...

run_linter unparam ./...

git ls-files -- 'Makefile' '*.go' '*.mod' '*.sh' '*.yaml' '*.yml'\
	| xargs misspell --error

run_linter looppointer ./...

run_linter nilness ./...

# TODO(a.garipov): Add fieldalignment?

run_linter -e shadow --strict ./...

# TODO(a.garipov): Enable in v0.108.0.
# run_linter gosec --quiet ./...

# TODO(a.garipov): Enable --blank?
run_linter errcheck --asserts ./...

run_linter staticcheck ./...
