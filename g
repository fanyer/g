#!/bin/bash

#
# Settings
#
MIRROR_PATTERN=${OO_MIRROR_PATTERN-https://codeload.github.com/golang/go/tar.gz/go%s}
BUILD_CMD=${OO_BUILD_CMD-./make.bash}

if [ ! -z "${OO_BOOTSTRAP_VERSION}" ]; then
    BOOTSTRAP_VERSION=${OO_BOOTSTRAP_VERSION}
fi

#
# Global Vars
#
ROOT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE:-$_}")/.." && pwd -P)
VERSIONS_DIR=${ROOT_DIR}/versions
GOROOT_DIR=${ROOT_DIR}/go
GOBIN_PATH=${GOROOT_DIR}/bin/go

VERSION=$(cat ${ROOT_DIR}/VERSION)

#
# Help
#
show_help() {
    cat <<-EOF
Usage: gpm [COMMAND]

Commands:
  gpm                         Output current go version
  gpm ls                      Output versions installed
  gpm <version>               Use go <version>
  gpm use <version>           Use go <version>
  gpm get <version>           Get go <version>
  gpm rm <version>            Remove the given version
  gpm as <version>            Run go from gpm on a specific version
  gpm dir [<version>]         Show go directory by version
  gpm bin [<version>]         Show go binary path by version
  gpm build <version>         Build go by version
  gpm env                     Output current go env
  gpm upgrade                 Upgrade gpm to latest version

Options:
  -v, --version              Output oo's version
  -h, --help                 Output this help message

Environment Variables:
  OO_MIRROR_PATTERN          Mirror url pattern to download go source tarball
                             default: https://codeload.github.com/golang/go/tar.gz/go%s
  OO_BUILD_CMD               Command to build go from source, default: ./make.bash
  OO_BOOTSTRAP_VERSION       Bootstrap go version to compile the target version,
                             default: the latest installed version

Version: ${VERSION}
EOF
    exit 0
}

# https://gist.github.com/livibetter/1861384
source "vercmp.sh"

show_version() {
    echo ${VERSION}
    exit 0
}

abort() {
    echo $1 && exit 1
}

#
# Show current version
#
current() {
    if [ -f ${GOROOT_DIR}/VERSION ]; then
        printf '%s\n' $(cat ${GOROOT_DIR}/VERSION)
    else
        echo $(go version) || abort 'go? (no version installed)'
    fi
}

#
# List all versions installed
#
list() {
    for file in ${VERSIONS_DIR}/*
    do
        if [ -d ${file} ]; then
            basename ${file}
        fi
    done
}

#
# Use a version
#
use() {
    test -z $1 && show_help
    target_dir=${VERSIONS_DIR}/$1
    test -d ${target_dir} || abort 'not installed'
    # create soft link
    test -f ${GOROOT_DIR} && rm ${GOROOT_DIR}
    test -d ${GOROOT_DIR} && rm -r ${GOROOT_DIR}
    ln -fs ${target_dir} ${GOROOT_DIR}
    printf '=> ' && echo $(current)
}

#
# Remove a version
#
remove() {
    test -z $1 && show_help
    target_dir=${VERSIONS_DIR}/$1
    test -d ${target_dir} || abort 'not installed'

    if [ -d ${GOROOT_DIR} ] && \
        [ $(readlink ${GOROOT_DIR}) = ${target_dir} ]; then
        rm ${GOROOT_DIR} && printf 'go@%s deused\n' $1
    fi

    rm -r ${target_dir}
    printf 'go@%s removed\n' $1
}

#
# Get a version
#
handle_get_sigint() {
    printf '\ncanceled, clean up..\n' $1
    remove $1
    exit 1
}

handle_get_sigtstp() {
    printf '\nstopped, clean up..\n' $1
    remove $1
    exit 1
}

#
# Get new version installed
#
get() {
    test -z $1 && show_help
    version=$1
    tarball_url=$(printf ${MIRROR_PATTERN} ${version})
    target_dir=${VERSIONS_DIR}/${version}
    test -d ${target_dir} && abort 'already installed'
    command -v curl > /dev/null || abort 'curl is required'
    test -d ${target_dir} || mkdir -p ${target_dir}
    trap 'handle_get_sigint ${version}' INT
    trap 'handle_get_sigtstp ${version}' SIGTSTP
    printf 'get %s..\n' ${tarball_url}
    curl -# -L ${tarball_url} | tar xz -C ${target_dir} --strip 1 &> /dev/null

    if [ ${?} != 0 ]; then
        rm -rf ${target_dir} && abort 'fetch souce failed, maybe bad version'
    fi

    build ${version}
    use ${version}
}


#
# Build go
#
build() {
    if [ -z $1 ]; then
        abort 'require argument version'
    else
        version=$1
    fi

    target_dir=${VERSIONS_DIR}/${version}
    test ! -d $target_dir && abort 'not installed'

    printf 'build %s..\n' ${version}

    # go1.5 requires go>=1.4 as build tool (no more gcc)
    vercmp ${version} '1.5'
    ret=$?

    if [ "${ret}" == 0 ] || [ "${ret}" == 1 ] ; then
        if [ -z "${BOOTSTRAP_VERSION}" ]; then
            bootstrap_version=0
            for d in $(ls -d ${VERSIONS_DIR}/* | xargs -n 1 basename); do
                vercmp ${d} ${bootstrap_version}
                if [ "${?}" == 1 ] && [ "${d}" != "${version}" ]; then
                    bootstrap_version=${d}
                fi
            done
        else
            bootstrap_version=${BOOTSTRAP_VERSION}
        fi

        vercmp ${bootstrap_version} '1.4'
        if [ "${?}" == 2 ]; then
            abort 'bootstrap go required to be >= 1.4'
        fi

        test ! -d ${VERSIONS_DIR}/${bootstrap_version} && abort "bootstrap version not installed"

        printf "using go%s to bootstrap go%s..\n" ${bootstrap_version} ${version}..
        export GOROOT_BOOTSTRAP=${VERSIONS_DIR}/${bootstrap_version}
    fi

    cd ${target_dir}/src && ${BUILD_CMD} &> /dev/null || abort 'build failed'
    printf "build successfully\n"
}


#
# Show go dir
#
dir() {
    if [ -z $1 ]; then
        printf ${GOROOT_DIR}
    else
        printf ${VERSIONS_DIR}/$1
    fi
}

#
# Show go bin
#
bin() {
    if [ -z $1 ]; then
        printf ${GOROOT_DIR}/bin/go
    else
        printf ${VERSIONS_DIR}/$1/bin/go
    fi
}


#
# Run as go version
#
as() {
    test -z $1 && show_help
    version=$1
    target_dir=${VERSIONS_DIR}/${version}
    test ! -d $target_dir && abort 'not installed'
    target_bin=${target_dir}/bin/go
    exec "${target_bin}" "${@:2}"
}

#
# Show current go env
#
env() {
    exec "${GOBIN_PATH}" env
}

#
# Upgrade oo
#
upgrade() {
    command -v git > /dev/null 2>&1 || abort 'git not installed'
    cd ${ROOT_DIR} && git pull git://github.com/hit9/oo.git master
    printf '=> %s\n' $(cat ${ROOT_DIR}/VERSION)
}

#
# Main
#
if test $# -eq 0; then
    current
else
    case $1 in
        -v|--version) show_version ;;
        -h|--help|help) show_help ;;
        ls) list ;;
        get) get $2 ;;
        rm) remove $2 ;;
        as) as ${@:2} ;;
        use) use $2 ;;
        dir) dir $2 ;;
        bin) bin $2 ;;
        build) build $2 ;;
        env) env ;;
        upgrade) upgrade ;;
        *) use $1 ;;
    esac
fi
