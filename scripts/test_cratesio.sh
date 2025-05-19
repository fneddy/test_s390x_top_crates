#!/usr/bin/env bash
# set -x

OPTIONS=$(getopt -o hn:g:v:t: -l help,name:,git:,name:,temp: -n "$0" -- "$@")

# Exit if the parsing fails
if [ $? != 0 ]; then
	echo "Failed to parse options." >&2
	exit 1
fi

help() {
	printf " $0
	-h --help		print this help
	-n --name [NAME]	crate name under test
	-v --version [VERSION]	version of the crate to test
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
		-n | --name)
			NAME="$2"
			shift 2
		;;
		-v | --version)
			VERSION="$2"
			shift 2
		;;
		-t | --temp)
			TEMP="$2"
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
if [ -z "${VERSION}" ]; then
	VERSION=$(curl -s https://crates.io/api/v1/crates/${NAME} | jq -r ".crate.newest_version")
	echo "[$NAME] fetch crates.io version: ${VERSION}"
fi

echo "[$NAME] download directory: ${TEMP}/${NAME}-${VERSION}"

# create nedded folders
rm -rf ${TEMP}/${NAME}-${VERSION}
#mkdir -p ${TEMP}/${NAME}-${VERSION}
cd ${TEMP}/

# fetch the source
set -x
curl -sL "https://crates.io/api/v1/crates/${NAME}/${VERSION}/download" | tar xzf -

# test the crate
cd ${TEMP}/${NAME}-${VERSION}
cargo clean
cargo +stable test "$@"
RESULT="$?"

cd ${TEMP}
rm -rf "${TEMP}/${NAME}-${VERSION}"
exit ${RESULT}
set +x
