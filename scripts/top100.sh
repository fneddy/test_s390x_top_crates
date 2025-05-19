#!/usr/bin/env bash
export ARTIFACTS=/tmp/top100_artifacts
export TOPLIST=/tmp/top100
export REPORT=/tmp/top100_report
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"
export DATE=$(date)

rm -rf ${REPORT}
git clone git@github.com:fneddy/test_s390x_top_crates.git ${REPORT}

./nebula.sh -c 100 \
	-g syn=https://github.com/dtolnay/syn -p syn="--release --features test" -v syn=2.0.0 \
	-g tokio=https://github.com/tokio-rs/tokio/ -v tokio=tokio-1.45.0

cd ${REPORT}
git config user.name "cronjob (Eduard Stefes)"
git config user.email "eduard.stefes@ibm.com"

PASS_COUNT=$(cat run.log | grep pass | wc -l)
FAIL_COUNT=$(cat run.log | grep fail | wc -l)
FAILED=$(cat run.log | grep fail)

cat > README <<EOF
Testresults as of ${DATE}
PASS: ${PASS_COUNT}
FAIL: ${FAIL_COUNT}

FAILED_CRATES:
${FAILED}
EOF

git add .
git commit -F README
git push origin
