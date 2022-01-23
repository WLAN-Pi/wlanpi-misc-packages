#!/bin/bash

PARSED_ARGS=$(getopt -o cfhaj: --long clean,force-sync,help,all --long arch:,package: -- "$@")
VALID_ARGS=$?

SCRIPT_PATH="$(dirname $(readlink -f "$0"))"
CACHE_PATH="${SCRIPT_PATH}/source"
LOG_PATH="${SCRIPT_PATH}/logs"

BUILD_ARCH="armhf"
CLEAN_PACKAGE="0"
FORCE_SYNC="0"
NUM_CORES=$(($(nproc)/2))
EXEC_FUNC=""
BUILD_ALL="0"
BUILD_PACKAGE=""
export DEBFULLNAME="Daniel Finimundi"
export DEBEMAIL="daniel@finimundi.com"

mkdir -p "${LOG_PATH}"

usage()
{
    echo "Usage: $0 [ -c | --clean ] [ -f | --force-sync ]
                    [ --arch ARCH ]
                    [ -a | --all ]
                    [ --package ]
                    [ -j CORES ]
                    [ -h | --help ]"
}

process_options()
{
    if [ "$VALID_ARGS" != 0 ]; then
        usage
        exit 1
    fi

    eval set -- "${PARSED_ARGS}"

    while true; do
        case "$1" in
            --arch )
                BUILD_ARCH="$2"
                shift 2
                ;;
            -c | --clean )
                CLEAN_PACKAGE="1"
                shift 1
                ;;
            -f | --force-sync )
                FORCE_SYNC="1"
                shift 1
                ;;
            -j )
                case "$2" in
                    x|X) NUM_CORES=$(nproc) ;;
                    *) NUM_CORES="$2" ;;
                esac
                shift 2
                ;;
            -h | --help )
                usage
                exit 0
                ;;
            -a | --all )
                BUILD_ALL="1"
                shift 1
                ;;
            --package )
                BUILD_PACKAGE="$2"
                shift 2
                ;;
            -- )
                EXEC_FUNC="$2"
                shift 2
                break
                ;;
            *) usage; exit 1 ;;
        esac
    done

    if [ -z "${BUILD_PACKAGE}" ] && [ "${BUILD_ALL}" != "1" ]; then
        log "err" "Either build all packages with --all option or choose one with --package <package_name>"
        usage
        exit 1
    fi
}

build_packages()
{
    log "ok" "Syncing sbuild submodule"
    git submodule update --init --recursive

    commit_msg=""
    for package_conf in "${SCRIPT_PATH}"/*.conf; do
        unset package_name package_url package_ref package_version package_version_type
        source "${package_conf}"

        if [ "${BUILD_ALL}" != "1" ] && [ "${BUILD_PACKAGE}" != "${package_name}" ]; then
            log "warn" "Skipping package ${package_name}"
            continue
        fi

        log "ok" "Packaging ${package_name}"
        set -e

        package_path="${SCRIPT_PATH}/${package_name}"
        package_debian_path="${SCRIPT_PATH}/debians/${package_name}"

        download_source "${package_url}" "${package_ref}" "${package_name}" "${package_version_type}"

        # Copy debian files to source dir
        mkdir -p "${package_path}/debian"
        rsync -aq "${package_debian_path}"/* "${package_path}"/debian/

        if [ "${package_version_type}" == "date" ]; then
            commit_date="$(cd ${package_path}; git show -s --format=%ct HEAD)"
            upstream_version="$(date -d "@$commit_date" -u +1.%Y%m%d)-1"
        else
            upstream_version="$(cd ${package_path}; git describe --tags)"
            upstream_version="$(echo "${upstream_version}" | sed 's/^[a-zA-Z-]*//' | tr '-' '.')-1"
        fi

        if $(dpkg --compare-versions "${upstream_version}" gt "${package_version}"); then
            package_version="${upstream_version}wlanpi1"
        fi

        log "Using version ${package_version} for ${package_name}"
        (cd "${package_path}"; dch -v "${package_version}" -D bullseye --force-distribution "${package_name} version ${package_version}")
        cp "${package_path}/debian/changelog" "${package_debian_path}/changelog"

        git add "${package_debian_path}/changelog"
        commit_msg="${commit_msg}
Packaged ${package_name} version ${package_version}"

        if [ "${BUILD_ALL}" != "1" ]; then
            git commit -m "Release ${package_name} version ${package_version}" -m "${commit_msg}"
        fi

        log "ok" "Build Debian package for (${BUILD_ARCH})"
        (
            cd "${package_path}"
            git archive --format=tar HEAD | xz -T0 > "../${package_name}_${package_version%-*}.orig.tar.xz"
            INPUTS_ARCH=${BUILD_ARCH} INPUTS_DISTRO="bullseye" INPUTS_RUN_LINTIAN="false" "${SCRIPT_PATH}"/sbuild-debian-package/build.sh
        )
    done

    if [ "${BUILD_ALL}" == "1" ]; then
        git commit -m "Release all packages" -m "${commit_msg}"
    fi
}

download_source()
{
    url="$1"
    ref="$2"
    target_package="$3"
    shallow="$4"
    target_path="${SCRIPT_PATH}/${target_package}"

    fetch_depth="--depth=1"
    if [ "${shallow}" == "describe" ]; then
        unset fetch_depth
        unshallow="--unshallow"
    fi

    if [ ! -d "${target_path}" ]; then
        log "ok" "Downloading ${target_package} source from ${url}, branch ${ref}"
        git clone ${fetch_depth} -b "${ref}" "${url}" "${target_path}"
    elif [ "${FORCE_SYNC}" == "1" ]; then
        log "ok" "Fetching new ${target_package} version on branch ${ref}"
        pushd "${target_path}" >/dev/null

        git remote set-branches origin "${ref}"
        git fetch -q ${fetch_depth} ${unshallow} origin "${ref}"

        if [ "${CLEAN_PACKAGE}" == "1" ]; then
            git reset --hard
            git clean -fdx
        fi

        git co -B "${ref}" origin/"${ref}"

        if [ $? -ne 0 ]; then
            log "error" "Couldn't checkout to new ${target_package} version. Try executing again with --clean arg to reset the workspace"
            exit 3
        fi

        popd >/dev/null
    else
        log "warn" "${target_package} already downloaded. Please use --force-sync if you want to update it."
    fi
}

log()
{
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    ORANGE='\033[0;33m'
    NC='\033[0m'

    if [ "$1" == "ok" ]; then
        echo -en "${GREEN}[ OK ]${NC} "
    elif [ "$1" == "error" ]; then
        echo -en "${RED}[ ERROR ]${NC} "
    elif [ "$1" == "warn" ]; then
        echo -en "${ORANGE}[ WARN ]${NC} "
    fi
    echo "$2"
}

process_options
build_packages
