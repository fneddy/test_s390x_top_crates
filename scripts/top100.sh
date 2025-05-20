#!/usr/bin/env bash
export ARTIFACTS=/var/tmp/top100_artifacts
export TOPLIST=/tmp/top100
export REPO=/tmp/top100_report
export REPORT=${REPO}/log
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"
export DATE=$(date)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

rm -rf ${REPO}
git clone git@github.com:fneddy/test_s390x_top_crates.git ${REPO}

${SCRIPT_DIR}/nebula.sh -c 100 \
	-g syn=https://github.com/dtolnay/syn -p syn="--release --features test" -v syn=2.0.0 \
	-g tokio=https://github.com/tokio-rs/tokio/ -v tokio=tokio-1.45.0 \
	-g regex-automata=https://github.com/rust-lang/regex.git -v regex-automata=regex-automata-0.4.9 -p regex-automata="--manifest-path regex-automata/Cargo.toml --test integration" \
	-g futures-channel=https://github.com/rust-lang/futures-rs.git -v futures-channel=0.3.31 -p futures-channel="--manifest-path futures-channel/Cargo.toml" \
	-p lazy_static=" -- --skip ui" \
	-k memchr


cd ${REPO}
git config user.name "cronjob (Eduard Stefes)"
git config user.email "eduard.stefes@ibm.com"

PASS_COUNT=$(cat ${REPORT}/run.log | grep pass | wc -l)
FAIL_COUNT=$(cat ${REPORT}/run.log | grep fail | wc -l)
FAILED=$(cat ${REPORT}/run.log | grep fail)

cat > ${REPO}/README <<EOF
Testresults as of ${DATE}
PASS: ${PASS_COUNT}
FAIL: ${FAIL_COUNT}

FAILED_CRATES:
${FAILED}
EOF

git add .
git commit -F README
git push origin
