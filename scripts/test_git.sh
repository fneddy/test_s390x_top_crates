#!/usr/bin/env bash
# set -x

OPTIONS=$(getopt -o hn:g:b:t: -l help,name:,git:,branch:,temp: -n "$0" -- "$@")

# Exit if the parsing fails
if [ $? != 0 ]; then
	echo "Failed to parse options." >&2
	exit 1
fi

help() {
	printf " $0
	-h --help		print this help
	-n --name [NAME]	crate name under test
	-g --git [URI]	try to load from git instead of crates.io
	-b --branch [GIT_BRANCH] the git branch to checkout (default HEAD)
	-t --temp [TEMPDIR]	tempdir to use
	[--]	[cargo-option] pass cargo options after --
"
}

eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-h | --help)
			help
			exit 0
		;;
		-g | --git)
			GIT_URL="$2"
			shift 2
		;;
		-n | --name)
			NAME="$2"
			shift 2
		;;
		-t | --temp)
			TEMP="$2"
			shift 2
		;;
		-b | --branch)
			GIT_BRANCH="$2"
			shift 2
		;;
		--)
			shift
			break
		;;
		*)
			break
		;;
	esac
done

TEMP=${TEMP:-$(mktemp -d)}

if [ -z "${NAME}" ]; then
	echo "-n [NAME] is a required parameter" >&2
	exit 1
fi

# fetch crate version if not given
if [ -z "${GIT_BRANCH}" ]; then
	GIT_BRANCH=$(curl -s https://crates.io/api/v1/crates/${NAME} | jq -r ".crate.newest_version")
	echo "[$NAME] fetch crates.io version: ${GIT_BRANCH}"
fi

echo "[$NAME] download directory: ${TEMP}/${NAME}-${GIT_BRANCH}"

# create nedded folders
rm -rf ${TEMP}/${NAME}-${GIT_BRANCH}
mkdir -p ${TEMP}/${NAME}-${GIT_BRANCH}
cd ${TEMP}/${NAME}-${GIT_BRANCH}

# fetch the source
set -x
git clone -c advice.detachedHead=false -q --branch ${GIT_BRANCH} --depth 1 ${GIT_URL} .

# test the crate
cargo clean
cargo +stable test $@
RESULT="$?"

cd ${TEMP}
rm -rf "${TEMP}/${NAME}-${GIT_BRANCH}"
exit ${RESULT}

set +x
