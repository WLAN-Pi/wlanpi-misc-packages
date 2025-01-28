#!/bin/bash

PARSED_ARGS=$(getopt -o cfhaj: --long clean,force-sync,help,all --long arch:,package:,distro: -- "$@")
VALID_ARGS=$?

SCRIPT_PATH="$(dirname $(readlink -f "$0"))"
CACHE_PATH="${SCRIPT_PATH}/source"
LOG_PATH="${SCRIPT_PATH}/logs"
COMMIT_MSG_FILE="${SCRIPT_PATH}/commit_msg.txt"

BUILD_ARCH="arm64"
CLEAN_PACKAGE="1"
FORCE_SYNC="0"
NUM_CORES=$(($(nproc)/2))
EXEC_FUNC=""
BUILD_ALL="0"
BUILD_PACKAGE=""
DISTRO="bullseye"
export DEBFULLNAME="Daniel Finimundi"
export DEBEMAIL="daniel@finimundi.com"

mkdir -p "${LOG_PATH}"

usage()
{
    echo "Usage: $0 [ -c | --clean ] [ -f | --force-sync ]
                    [ --arch ARCH ]
                    [ --distro DISTRO ]
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
            --distro )
                BUILD_DISTRO="$2"
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

sanitize_version() {
    local version="$1"
    # Remove leading non-digit characters
    version=$(echo "$version" | sed -E 's/^[^0-9]*//')
    # Replace both underscores and hyphens with dots
    version=$(echo "$version" | tr '_-' '..')
    # Ensure it starts with a digit
    if [[ ! "$version" =~ ^[0-9] ]]; then
        version="0.${version}"
    fi
    echo "$version"
}

build_packages()
{
    log "ok" "Syncing sbuild submodule"
    git submodule update --init --recursive

    echo "" > "${COMMIT_MSG_FILE}"

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
            upstream_version="$(date -d "@$commit_date" -u +1.%Y%m%d)"
        else
            # Try direct ref sanitization first
            upstream_version=$(sanitize_version "${ref}")

            # Fallback to git describe if needed
            if [ -z "$upstream_version" ] || [ "$upstream_version" == "0." ]; then
                set +e
                upstream_version="$(cd ${package_path}; git describe --tags 2>/dev/null)"
                upstream_version=$(sanitize_version "$upstream_version")
                set -e
            fi
        fi

        if $(dpkg --compare-versions "${upstream_version}" gt "${package_version}"); then
            package_version="${upstream_version}"
        fi

        # Get upstream version. E.g. version 1.2.3-4wlanpi1 will be 1.2.3
        current_version="$(cd ${package_path}; dpkg-parsechangelog --show-field Version)"
        current_upstream_version=${current_version%%-*}
        
        # Debian build version. E.g. 1.2.3-4wlanpi1 will be 4
        current_deb_version=${current_version%wlanpi*}
        current_deb_version=${current_deb_version#*-}
  
        log "info" "upstream_version: ${upstream_version}"
        log "info" "package_version: ${package_version}"
        log "info" "current_upstream_version: ${current_upstream_version}"

        deb_version="1"
        if $(dpkg --compare-versions "${package_version}" eq "${current_upstream_version}"); then
            log "warn" "Upstream version is the same as last built. Incrementing debian build number."
            deb_version=$((current_deb_version+1))
        elif $(dpkg --compare-versions "${package_version}" lt "${current_upstream_version}"); then
            log "warn" "Trying to build an old version of upstream source. Please check version information. Skipping build."
            continue
        fi
        package_version="${package_version}-${deb_version}wlanpi1"

        if [ -n "$GITHUB_OUTPUT" ]; then
            echo "package-version=${package_version}" >> $GITHUB_OUTPUT
        fi

        log "Using version ${package_version} for ${package_name}"
        (cd "${package_path}"; dch -v "${package_version}" -D "${BUILD_DISTRO}" --force-distribution "${package_name} version ${package_version}")
        cp "${package_path}/debian/changelog" "${package_debian_path}/changelog"

        git add "${package_debian_path}/changelog"
        echo "Packaged ${package_name} version ${package_version}" >> "${COMMIT_MSG_FILE}"

        log "ok" "Build Debian package for (${BUILD_ARCH})"
        (
            cd "${package_path}"
            # git archive --format=tar --prefix="${package_name}-${upstream_version}/" HEAD | xz > "../${package_name}_${upstream_version}.orig.tar.xz"
            git archive --format=tar HEAD | xz -T0 > "../${package_name}_${package_version%-*}.orig.tar.xz"
            INPUTS_ARCH=${BUILD_ARCH} INPUTS_DISTRO="${BUILD_DISTRO}" INPUTS_RUN_LINTIAN="false" INPUTS_INSTALL_AUTOCONF="true" "${SCRIPT_PATH}"/sbuild-debian-package/build.sh
            cp *.deb "${SCRIPT_PATH}"
        )
        package_built="1"
    done

    # Only commit if we actually built something
    if [ "${package_built}" == "1" ]; then
        git_commit
    fi
}

git_commit()
{
    git config --local user.email "${DEBEMAIL}"
    git config --local user.name "${DEBFULLNAME}"

    if [ "${BUILD_ALL}" == "1" ]; then
        sed -i "1s/^/Release all packages\n\n/" "${COMMIT_MSG_FILE}"
    else
        sed -i "1s/^/Release ${BUILD_PACKAGE}\n\n/" "${COMMIT_MSG_FILE}"
    fi

    git commit -F "${COMMIT_MSG_FILE}"
}

download_source()
{
    local url="$1"
    local ref="$2"
    local target_package="$3"
    local shallow="$4"
    local target_path="${SCRIPT_PATH}/${target_package}"
    local fetch_depth="--depth=1"

    if [ ! -d "${target_path}" ]; then
        log "ok" "Downloading ${target_package} source from ${url}"
        
        if [[ "${ref}" == iwlwifi-fw-* ]]; then
            # For iwlwifi firmware, just fetch the specific tag
            if ! git clone --depth=1 --branch "${ref}" "${url}" "${target_path}"; then
                log "error" "Failed to clone firmware tag ${ref}"
                # If specific tag fails, try normal clone as fallback
                if ! git clone --depth=1 "${url}" "${target_path}"; then
                    log "error" "Failed to clone repository from ${url}"
                    return 1
                fi
                # Try to fetch just the specific tag
                if ! git -C "${target_path}" fetch --depth=1 origin "refs/tags/${ref}:refs/tags/${ref}"; then
                    log "error" "Failed to fetch tag ${ref}"
                    return 1
                fi
            fi
        else
            # Normal clone for non-firmware packages
            if ! git clone "${fetch_depth}" "${url}" "${target_path}"; then
                log "error" "Failed to clone repository from ${url}"
                return 1
            fi
        fi

        log "ok" "Attempting to checkout ${ref}"
        
        if ! git -C "${target_path}" checkout "${ref}"; then
            log "error" "Could not find branch, tag, or commit '${ref}'"
            log "info" "Available branches:"
            git -C "${target_path}" branch -r
            log "info" "Available tags:"
            git -C "${target_path}" tag
            return 1
        fi
        log "ok" "Successfully checked out ${ref}"
        
    elif [ "${FORCE_SYNC}" = "1" ]; then
        log "ok" "Fetching new ${target_package} version for ${ref}"
        pushd "${target_path}" >/dev/null || exit
        
        if [[ "${ref}" == iwlwifi-fw-* ]]; then
            # For firmware, just fetch the specific tag
            git fetch --depth=1 origin "refs/tags/${ref}:refs/tags/${ref}" || true
        else
            # Normal fetch for other packages
            git fetch -q "${fetch_depth}" origin
        fi

        if [ "${CLEAN_PACKAGE}" = "1" ]; then
            git reset --hard
            git clean -fdx
        fi

        if ! git checkout "${ref}"; then
            log "error" "Could not find branch, tag, or commit '${ref}'"
            log "info" "Available branches:"
            git branch -r
            log "info" "Available tags:"
            git tag
            popd >/dev/null || exit
            return 1
        fi
        log "ok" "Successfully checked out ${ref}"

        popd >/dev/null || exit
    else
        log "warn" "${target_package} already downloaded. Please use --force-sync if you want to update it."
    fi
    return 0
}

log()
{
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    ORANGE='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    if [ "$1" == "ok" ]; then
        echo -en "${GREEN}[ OK ]${NC} "
    elif [ "$1" == "error" ]; then
        echo -en "${RED}[ ERROR ]${NC} "
    elif [ "$1" == "warn" ]; then
        echo -en "${ORANGE}[ WARN ]${NC} "
    elif [ "$1" == "info" ]; then
        echo -en "${BLUE}[ INFO ]${NC} "
    fi
    echo "$2"
}

process_options
build_packages
