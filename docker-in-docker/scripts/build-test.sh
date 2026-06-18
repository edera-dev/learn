#!/bin/sh
#
# build-test.sh — Run a standalone docker build to verify DinD works.
#
# The ci-job container already builds on startup, but you can run this
# inside the dind container for an additional demonstration.
#

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

printf "${BOLD}Running a docker build inside this pod...${NC}\n\n"

TMPDIR=$(mktemp -d)
cat > "$TMPDIR/Dockerfile" << 'DOCKERFILE'
FROM alpine:3.19
RUN apk add --no-cache curl
RUN echo "Built at $(date -u)" > /build-proof.txt
CMD ["cat", "/build-proof.txt"]
DOCKERFILE

printf "${CYAN}Building...${NC}\n"
docker build -t build-proof:latest "$TMPDIR" 2>&1 | tail -10

printf "\n${CYAN}Running the built image:${NC}\n"
docker run --rm build-proof:latest

printf "\n${GREEN}docker build works inside this pod.${NC}\n"

rm -rf "$TMPDIR"
docker rmi build-proof:latest > /dev/null 2>&1 || true
