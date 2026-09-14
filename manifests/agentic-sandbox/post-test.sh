#!/bin/bash

ARTIFACTS_DIR="${ARTIFACTS:-/logs/artifacts}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)
SCRIPT_REL_PATH=$(realpath --relative-to="${REPO_ROOT}" "$0")
mkdir -p "${ARTIFACTS_DIR}/hooks-output/$(dirname "${SCRIPT_REL_PATH}")"
# Log everything to a file in the artifacts directory, helpful for debugging if things go wrong
exec 2> >(tee "${ARTIFACTS_DIR}/hooks-output/${SCRIPT_REL_PATH}.log" >&2)
set -exuo pipefail

# Whether to run original post-test script
RUN_ORIGINAL_SCRIPTS="${RUN_ORIGINAL_SCRIPTS:-true}"
# Root directory for pprof artifacts
PPROF_OUTPUT_ROOT="${PPROF_OUTPUT_ROOT:-${ARTIFACTS_DIR}/pprofs}"
# Pattern for pprof artifacts
PPROF_ARTIFACTS_PATTERN="PodPeriodicCommand-*-cilium-pprof-stdout_*.txt"

for file in "${ARTIFACTS_DIR}"/${PPROF_ARTIFACTS_PATTERN}; do
    [ -e "$file" ] || continue

    FILENAME=$(basename "$file")
    OUTPUT_DIR="${PPROF_OUTPUT_ROOT}/${FILENAME%.*}"

    echo "Processing file: $FILENAME"
    mkdir -p "$OUTPUT_DIR"

    # 1. Search for Gzip Magic Header (0x1F 0x8B)
    OFFSET_GZIP=$(LC_ALL=C grep -a -b -o -m 1 $'\x1F\x8B' "$file" | cut -d: -f1)

    if [ -n "$OFFSET_GZIP" ]; then
        echo "Found Gzip signature at offset $OFFSET_GZIP."
        tail -c +$((OFFSET_GZIP + 1)) "$file" > "$OUTPUT_DIR/clean_profile.pb.gz"

        if tar -tzf "$OUTPUT_DIR/clean_profile.pb.gz" >/dev/null 2>&1; then
            echo "Payload is a compressed TAR archive (.tar.gz). Unpacking..."
            tar -C "$OUTPUT_DIR" -zxvf "$OUTPUT_DIR/clean_profile.pb.gz"
            rm "$OUTPUT_DIR/clean_profile.pb.gz"
        else
            echo "Payload is a standalone Gzip profile (.pb.gz)."
        fi
    else
        # 2. Search for POSIX Tar Marker ("ustar")
        # "ustar" is located at offset 257 of standard header block
        OFFSET_USTAR=$(LC_ALL=C grep -a -b -o -m 1 "ustar" "$file" | cut -d: -f1)

        if [ -n "$OFFSET_USTAR" ]; then
            NOISE_LIMIT=$((OFFSET_USTAR - 257))
            echo "Found Tar marker at offset $OFFSET_USTAR (Noise limit deduced: $NOISE_LIMIT bytes)."

            tail -c +$((NOISE_LIMIT + 1)) "$file" > "$OUTPUT_DIR/clean_archive.tar"

            if tar -tf "$OUTPUT_DIR/clean_archive.tar" >/dev/null 2>&1; then
                echo "Payload is an uncompressed TAR archive (.tar). Unpacking..."
                tar -C "$OUTPUT_DIR" -xvf "$OUTPUT_DIR/clean_archive.tar"
                rm "$OUTPUT_DIR/clean_archive.tar"
            else
                echo "Failed to unpack detected TAR stream."
            fi

        else
            echo "Skipping: Failed to recognize valid Gzip or Tar signature in this file."
            continue
        fi
    fi

    # 3. Invoke pprof descriptors for all extracted files in this subdirectory
    find "$OUTPUT_DIR" -type f | while read -r prof; do
        profile_name="${prof##*/}"
        output_path="${prof%/*}/${profile_name}-generated"

        if [[ "$profile_name" == "pprof-cpu" ]] || [[ "$profile_name" == "pprof-heap" ]] || [[ "$profile_name" == "pprof-trace" ]]; then
            mkdir -p "${output_path}"
        fi

        if [[ "$profile_name" == "pprof-cpu" ]]; then
            go tool pprof -svg "$prof" > "${output_path}/graph.svg"
            go tool pprof -text -nodecount=100 "$prof" > "${output_path}/top100.txt"
            go tool pprof -text -cum -nodecount=100 "$prof" > "${output_path}/cum100.txt"
            go tool pprof -tree -nodecount=50 "$prof" > "${output_path}/tree.txt"
        fi

        if [[ "$profile_name" == "pprof-heap" ]]; then
            go tool pprof -svg "$prof" > "${output_path}/graph.svg"
            for sample in inuse_space alloc_space inuse_objects alloc_objects; do
                go tool pprof -sample_index=$sample -svg "$prof" > "${output_path}/${sample}.svg"
                go tool pprof -sample_index=$sample -text -nodecount=100 "$prof" > "${output_path}/${sample}_top100.txt"
            done
        fi

        if [[ "$profile_name" == "pprof-trace" ]]; then
            for type in net sync syscall sched; do
                go tool trace -pprof=$type "$prof" > "${output_path}/${type}.prof"
                go tool pprof -svg "${output_path}/${type}.prof" > "${output_path}/${type}.svg"
                go tool pprof -text -nodecount=100 "${output_path}/${type}.prof" > "${output_path}/${type}_top100.txt"
                rm "${output_path}/${type}.prof"
            done
        fi
    done

    rm "$file"
done

if [[ $RUN_ORIGINAL_SCRIPTS == "true" ]]; then
  echo "Running original post-test script..."
  "${GOPATH}"/src/gke-internal.googlesource.com/test-infra/perf-tests/run-post-test.sh "$@"
fi
