#!/usr/bin/env bash
#set -x
OPTIONS=$(getopt -o c:s:k:r:p:g:v:h -l count:,sortby:,skip:,report:,param:,git:,version:,help -n "$0" -- "$@")
COUNT="${COUNT:-100}"
SORTBY="${SORTBY:-downloads}"
TOPLIST="${TOPLIST:-$(mktemp)}"
ARTIFACTS="${ARTIFACTS:-$(mktemp -d)}"
SKIPPED_IDS=${SKIPPED_IDS:-()}
REPORT="${REPORT:-$PWD}"
REPORT_LOCK=$(mktemp)
NPROC="${NPROC:-$( nproc )}"
declare -A PARAMS
declare -A GIT
declare -A VERSIONS
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd ${SCRIPT_DIR}

source $HOME/.cargo/env

# Exit if the parsing fails
if [ $? != 0 ]; then
	echo "Failed to parse options." >&2
	exit 1
fi

help() {
	printf " $0
	-h --help		print this help
	-c --count 	[NUM]		how many entries to get (default 100)
	-s --sortby 	[ATTRIBUTE]	sort result by atribute (default crate download count)
	-k --skip 	[NAME]		skip crate [NAME], repeate for multiple
	-r --report 	[PATH]		write report to directory [PATH] (default .)
	-p --param 	[CRATE_NAME]=[PARAM]		add PARAM to cargo test
	-v --version 	[CRATE_NAME]=[VERSION]		use this crate version
	-g --git 	[CRATE_NAME]=[GIT_URL]	try to load from git instead of crates.io
"
}

log() {
	local report_file="$2"
	flock "${REPORT_LOCK}" -c "echo \"$1\""
	if [ -n "${report_file}" ]; then
		flock "${REPORT_LOCK}" -c "echo $1 >> ${report_file}"
	fi
}


eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-k | --skip)
			SKIPPED_IDS+=("$2")
			shift 2
		;;
		-r | --report)
			REPORT=$(realpath "$2")
			shift 2
		;;
		-c | --count)
			COUNT="$2"
			shift 2
		;;
		-s | --sortby)
			SORTBY="$2"
			shift 2
		;;
		-h | --help)
			help
			exit 0
		;;
		-p | --param)
			arg=$2
	 		key="${arg%%=*}" # Everything before the first '='
			value="${arg#*=}" # Everything after the first '='
			PARAMS["$key"]="$value"
			shift 2
		;;
		-g | --git)
			arg=$2
			key="${arg%%=*}" # Everything before the first '='
			value="${arg#*=}" # Everything after the first '='
			GIT["$key"]="$value"
			shift 2
		;;
		-v | --version)
			arg=$2
			key="${arg%%=*}" # Everything before the first '='
			value="${arg#*=}" # Everything after the first '='
			VERSIONS["$key"]="$value"
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

# setup directories and files
mkdir -p "${ARTIFACTS}"
pushd "${ARTIFACTS}" > /dev/null
mkdir -p "${REPORT}"
echo "ID VERSION RESULT" > "${REPORT}/run.log"

# download toplist
if [ ! -s "${TOPLIST}" ]; then
	printf "loading toplist: "
	touch "${TOPLIST}"
	TOTAL_PAGES=$(( (COUNT + 100 - 1) / 100 ))
	for (( PAGE=1; PAGE<=TOTAL_PAGES; PAGE++ )); do
		REMAINING=$(( COUNT - (PAGE - 1) * 100 ))
		RQ_COUNT=$(( REMAINING < 100 ? REMAINING : 100 ))
		printf "%d%% " $((100 - (REMAINING / TOTAL_PAGES)))
		curl -s "https://crates.io/api/v1/crates?page=${PAGE}&per_page=${RQ_COUNT}&sort=${SORTBY}" | jq -c '.crates[]' >> ${TOPLIST}
	done
	printf "\n"
fi

# download all crates
STEP=1
while read -r CRATE ; do
	ID="$(echo "${CRATE}" | jq -r '.id')"
	if [[ -z "${VERSIONS[${ID}]}" ]]; then
		VERSION="$(echo "${CRATE}" | jq -r '.newest_version')"
	else
		VERSION="${VERSIONS[${ID}]}"
	fi
	if [[ "${SKIPPED_IDS[@]}" =~ "${ID}" ]]; then
		log "[${STEP}/${COUNT}] ${ID} ${VERSION} skip" "${REPORT}/run.log"
		continue
	fi
	# parallize download
	(
		log "[${STEP}/${COUNT}] ${ID} ${VERSION} started" "${REPORT}/run.log"

		if [[ -n "${GIT[${ID}]}" ]]; then
			log "[${STEP}/${COUNT}] ${ID} ${VERSION} ${SCRIPT_DIR}/test_git.sh -n ${ID} -g ${GIT[${ID}]} -b ${VERSION} -t ${ARTIFACTS} -- ${PARAMS[${ID}]}" "${REPORT}/run.log"
			${SCRIPT_DIR}/test_git.sh -n "${ID}" -g "${GIT[${ID}]}" -b ${VERSION} -t "${ARTIFACTS}" -- "${PARAMS[${ID}]}" &> "${REPORT}/${ID}.${VERSION}.log"
			RESULT=$?
		else
			log "[${STEP}/${COUNT}] ${ID} ${VERSION} ${SCRIPT_DIR}/test_cratesio.sh -n ${ID} -v ${VERSION} -t ${ARTIFACTS} -- ${PARAMS[${ID}]} " "${REPORT}/run.log"
			${SCRIPT_DIR}/test_cratesio.sh -n "${ID}" -v "${VERSION}" -t "${ARTIFACTS}" -- "${PARAMS[${ID}]}" &> "${REPORT}/${ID}.${VERSION}.log"
			RESULT=$?
		fi
		if [ "${RESULT}" -eq "0" ]; then
			log "[${STEP}/${COUNT}] ${ID} ${VERSION} pass" "${REPORT}/run.log"
			rm ${REPORT}/${ID}.*.log
		else
			log "[${STEP}/${COUNT}] ${ID} ${VERSION} fail" "${REPORT}/run.log"
		fi
		log "[${STEP}/${COUNT}] ${ID} ${VERSION} finished" "${REPORT}/run.log"
	) &
	[ $( jobs -p | wc -l ) -ge "${NPROC}" ] && wait
	STEP=$((STEP + 1))
done < ${TOPLIST}
wait

popd > /dev/null

rm -rf "${TOPLIST}"
rm -rf "${ARTIFACTS}"
