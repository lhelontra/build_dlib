#!/bin/bash

# build_dlib -*- shell-script -*-
#
# The MIT License (MIT)
#
# Copyright (c) 2017 Leonardo Lontra
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
NC='\033[0m'
DLIB_SRC_FILENAME="dlib.zip"

DIR="$(realpath $(dirname $0))"
source "${DIR}/deps.sh"

function log_failure_msg() {
    echo -ne "[${RED}error${NC}] $@\n"
}


function log_warn_msg() {
    echo -ne "[${RED}warn${NC}] $@\n"
}


function log_app_msg() {
    echo -ne "[${BLUE}info${NC}] $@\n"
}

function yesnoPrompt() {
    local response=""
    read -p "$1" -r response
    [[ $response =~ ^[Yy]$ ]] && return 0
    return 1
}

function makeBuildDirAndGo() {
    # for python compilation
    [ "$PYTHON_SUPPORT" == "ON" ] && {
        mkdir -p ${WORKDIR}/dlib-${DLIB_VERSION}/tools/python/build/
        cd ${WORKDIR}/dlib-${DLIB_VERSION}/tools/python/build/
        return 0
    }
    # for c++ compilation
    mkdir -p ${WORKDIR}/dlib-${DLIB_VERSION}/build/
    cd ${WORKDIR}/dlib-${DLIB_VERSION}/build/
    return 0
}

function dw_dlib() {
  mkdir -p $WORKDIR

  if [ -d ${WORKDIR}/dlib-${DLIB_VERSION}/ ]; then
       log_app_msg "dlib exists."
       return 0
  fi

  local url="https://github.com/davisking/dlib/archive/${DLIB_VERSION}.zip"

  [ "$DLIB_VERSION" != "master" ] && url="https://github.com/davisking/dlib/archive/v${DLIB_VERSION}.zip"

  log_app_msg "Downloading dlib ${url} ..."
  wget --no-check-certificate -q -c $url -O "$DLIB_SRC_FILENAME" || return 1

  unzip -o $DLIB_SRC_FILENAME -d "$WORKDIR" 1>/dev/null || {
    log_failure_msg "error on uncompress dlib src"
    return 1
  }

  return 0
}

function dw_toolchain() {
    [ "$CROSS_COMPILER" != "yes" ] && return 0

    if [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/bin/" ]; then
        log_app_msg "toolchain exists."
        return 0
    fi

    log_app_msg "Downloading toolchain ${CROSSTOOL_URL}"

    mkdir -p ${WORKDIR}/toolchain/
    wget --no-check-certificate -q -c $CROSSTOOL_URL -O ${WORKDIR}/toolchain/toolchain.tar.xz || {
      log_failure_msg "error when download toolchain."
      return 1
    }

    tar xf ${WORKDIR}/toolchain/toolchain.tar.xz -C ${WORKDIR}/toolchain/ || {
      log_failure_msg "error when extract toolchain."
      return 1
    }

    rm -f ${WORKDIR}/toolchain/toolchain.tar.xz  &>/dev/null

    return 0
}

function cmakegen() {
    log_app_msg "execute cmake..."

    # clean build folder
    if [ -d ${WORKDIR}/dlib-${DLIB_VERSION}/build/ ] || [ -d ${WORKDIR}/dlib-${DLIB_VERSION}/tools/python/build/ ]; then
        log_warn_msg "Clean build files if you want compile for another target. Use $0 -c <configfile> --clean"
        sleep 1
    fi

    local deps_path="${WORKDIR}/cross_deps/deps/${CROSSTOOL_ARCH}"

    if [ "$CROSS_COMPILER" == "yes" ] && [ ! -d "${deps_path}" ]; then
        log_warn_msg "Cross-compiler without local dependencies. "
        sleep 1
    fi

    makeBuildDirAndGo

    if [ "$CROSS_COMPILER" == "yes" ]; then
        FLAGS+=" -DCMAKE_LINKER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ld"
        FLAGS+=" -DCMAKE_AR=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ar"
        FLAGS+=" -DCMAKE_NM=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-nm"
        FLAGS+=" -DCMAKE_OBJCOPY=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-objcopy"
        FLAGS+=" -DCMAKE_OBJDUMP=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-objdump"
        FLAGS+=" -DCMAKE_RANLIB=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ranlib"
        FLAGS+=" -DCMAKE_STRIP=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-strip"
        FLAGS+=" -DCMAKE_C_COMPILER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-gcc"
        FLAGS+=" -DCMAKE_CXX_COMPILER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-g++"

        # enable pkg-config if variable exists
        [ "$CROSS_COMPILER" == "yes" ] && [ -d "${deps_path}" ] && [ -f "${deps_path}/.pkgconfig" ] && {
            source "${deps_path}/.pkgconfig"
            export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
            FLAGS+=" -DPKG_CONFIG_EXECUTABLE=$(whereis pkg-config | awk '{ print $2 }')"
        }

        # finds the include folder of cross-compiler toolchain
        local gcc_version=$(${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-gcc -dumpversion)
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/include/c++/${gcc_version}" ] && C_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/include/c++/${gcc_version}"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/include" ] && C_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/$CROSSTOOL_NAME/sysroot/usr/include"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/include" ] && C_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/$CROSSTOOL_NAME/libc/usr/include"
        [ -d "${CROSSTOOL_DIR}/lib/gcc/${CROSSTOOL_NAME}/${gcc_version}/include" ] && C_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/lib/gcc/$CROSSTOOL_NAME/${gcc_version}/include"
        [ -d "${CROSSTOOL_DIR}/lib/gcc/${CROSSTOOL_NAME}/${gcc_version}/include-fixed" ] && C_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/lib/gcc/$CROSSTOOL_NAME/${gcc_version}/include-fixed"

        # finds the libraries folder of cross-compiler toolchain
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib" ] && C_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib" ] && C_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib" ] && C_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib" ] && C_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib"

        if [ -d "${deps_path}" ]; then
            [ -f "${deps_path}/.sysinclude" ] && C_CXX_FLAGS+=" $(cat "${deps_path}/.sysinclude")"
            [ -f "${deps_path}/.syslib" ] && C_CXX_FLAGS+=" $(cat "${deps_path}/.syslib")"
            [ -f "${deps_path}/.rpath_link" ] && C_CXX_FLAGS+=" $(cat "${deps_path}/.rpath_link")"
        fi

        local toolchain_sysroot=""
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot" ] && toolchain_sysroot+="\"${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot\""
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc" ] && toolchain_sysroot+="\"${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc\""

        # finds library outside cross_deps folder, if exists ld.so.conf.d
        local pre_root_path=""
        [ -f /etc/ld.so.conf.d/${CROSSTOOL_NAME}.conf ] && pre_root_path+="$(cat /etc/ld.so.conf.d/${CROSSTOOL_NAME}.conf | grep -v '^#' | tr '\n' ' ')"

        [ "$PYTHON_SUPPORT" == "ON" ] && {
            local toolchain_cmakefile="${WORKDIR}/dlib-${DLIB_VERSION}/tools/python/build/toolchain.cmake"
        } || {
            local toolchain_cmakefile="${WORKDIR}/dlib-${DLIB_VERSION}/build/toolchain.cmake"
        }

        FLAGS+=" -DCMAKE_TOOLCHAIN_FILE=$toolchain_cmakefile"

        echo "set(CMAKE_SYSTEM_NAME Linux)" > $toolchain_cmakefile
        echo "set (CMAKE_FIND_ROOT_PATH ${toolchain_sysroot} \"${pre_root_path}\" \"${deps_path}\")" >> $toolchain_cmakefile
        echo "set (CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)" >> $toolchain_cmakefile
        echo "set (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)" >> $toolchain_cmakefile
        echo "set (CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)" >> $toolchain_cmakefile

        [ "$PYTHON_SUPPORT" == "ON" ] && {

            if [ ! -d "${deps_path}" ] && [ -z "$(echo $FLAGS | grep -i PYTHON_INCLUDE_DIR)" ] && [ -z "$(echo $FLAGS | grep -i PYTHON_LIBRARY)" ]; then
                log_warn_msg "not found packages: libpython-dev${arch}"
                echo "Please runs this command: $0 -c <configfile> -dw-cross-deps \"libpython-dev${arch}\""
                echo "or define PYTHON_INCLUDE_DIR and PYTHON_LIBRARY in config."
                return 1
            fi

            # finds python libraries
            if [ -z "$(echo $FLAGS | grep -i PYTHON_INCLUDE_DIR)" ]; then
                [ "$PYTHON_VERSION" == "3" ] && {
                    FLAGS+=" -D PYTHON3=ON"
                    FLAGS+=" -DPYTHON_INCLUDE_DIR=$(find ${deps_path}/ -type d -wholename '*include/python3*')"
                    FLAGS+=" -DPYTHON_LIBRARY=$(find ${deps_path}/ -iname '*libpython3*.so' | tail -n1)"
                } || {
                    FLAGS+=" -DPYTHON_INCLUDE_DIR=$(find ${deps_path}/ -type d -wholename '*include/python2*')"
                    FLAGS+=" -DPYTHON_LIBRARY=$(find ${deps_path}/ -iname '*libpython2*.so' | tail -n1)"
                }
                # finds boost library
                FLAGS+=" -DBOOST_LIBRARYDIR=${deps_path}/usr/lib/$CROSSTOOL_NAME"
            fi
        }

    fi

    if [ ! -z "$C_CXX_FLAGS" ]; then
        log_app_msg "exporting cflags..."
        FLAGS+=" -DCMAKE_C_FLAGS=${C_CXX_FLAGS} -DCMAKE_CXX_FLAGS=${C_CXX_FLAGS}"
    fi

    FLAGS+=" .."
    cmake $FLAGS || return 1
}

function makedlib() {
    makeBuildDirAndGo
    [ "$USE_CORES" == "all" ] && USE_CORES=$(nproc)
    make -j $USE_CORES || {
        log_failure_msg "ERROR: failed make"
        return 1
    }
    return 0
}

function checkinstallgen() {
    makeBuildDirAndGo

    # extract version
    local version_major="$(sed -n 's/set(CPACK_PACKAGE_VERSION_MAJOR \"\(.*\)\")/\1/p' ${WORKDIR}/dlib-${DLIB_VERSION}/dlib/CMakeLists.txt)"
    local version_minor="$(sed -n 's/set(CPACK_PACKAGE_VERSION_MINOR \"\(.*\)\")/\1/p' ${WORKDIR}/dlib-${DLIB_VERSION}/dlib/CMakeLists.txt)"
    local version_patch="$(sed -n 's/set(CPACK_PACKAGE_VERSION_PATCH \"\(.*\)\")/\1/p' ${WORKDIR}/dlib-${DLIB_VERSION}/dlib/CMakeLists.txt)"
    local package_version="${version_major}.${version_minor}.${version_patch}"
    local package_name="${CHECKINSTALL_PKGNAME}"

    if [ "$PYTHON_SUPPORT" == "ON" ]; then
        [ "$PYTHON_VERSION" == "3" ] && package_name="python3-${package_name}" || package_name="python-${package_name}"
        local python_dir="$(python${PYTHON_VERSION} -c 'import site; print(site.getsitepackages()[0])')"
        mkdir -p .debian_package/$python_dir/
        cp dlib.so .debian_package/$python_dir/

        [ "$CROSS_COMPILER" == "yes" ] && local ARCH="$CROSSTOOL_ARCH" || local ARCH="$(dpkg --print-architecture)"
        local sizeof=$(du -k --total .debian_package/$python_dir/ | tail -n1 | awk '{ print $1 }')

        mkdir -p .debian_package/DEBIAN/
        echo "Package: $package_name" > .debian_package/DEBIAN/control
        echo "Priority: extra" >> .debian_package/DEBIAN/control
        echo "Section: dlib" >> .debian_package/DEBIAN/control
        echo "Installed-Size: $sizeof" >> .debian_package/DEBIAN/control
        echo "Maintainer: $CHECKINSTALL_MANTAINER" >> .debian_package/DEBIAN/control
        echo "Architecture: $ARCH" >> .debian_package/DEBIAN/control
        echo "Version: $package_version" >> .debian_package/DEBIAN/control
        echo "Provides: dlib" >> .debian_package/DEBIAN/control
        echo "Description: $CHECKINSTALL_SUMMARY" >> .debian_package/DEBIAN/control

        dpkg -b .debian_package/ ${package_name}_${package_version}_${ARCH}.deb || return 1
        echo "debian package: $(realpath ${package_name}_${package_version}_${ARCH}.deb)"
        return 0
    fi

    # prepare postinstall
    echo -ne '#!/bin/bash\n\n' > postinstall-pak
    echo "echo \"${CMAKE_INSTALL_PREFIX}/lib\" > /etc/ld.so.conf.d/dlib.conf" >> postinstall-pak
    echo "ldconfig" >> postinstall-pak
    chmod +x postinstall-pak

    CHECKINSTALL_FLAGS="-y --backup=no --install=no -D"
    [ "$CHECKINSTALL_INCLUDE_DOC" == "no" ] && CHECKINSTALL_FLAGS+=" --nodoc"
    CHECKINSTALL_FLAGS+=" --pkgname=${package_name}"
    CHECKINSTALL_FLAGS+=" --pkgversion=${package_version}"
    CHECKINSTALL_FLAGS+=" --pkgsource=$CHECKINSTALL_PKGSRC"
    CHECKINSTALL_FLAGS+=" --pkggroup=$CHECKINSTALL_PKGGROUP"
    CHECKINSTALL_FLAGS+=" --pkgaltsource=$CHECKINSTALL_PKGALTSRC"
    CHECKINSTALL_FLAGS+=" --maintainer=$CHECKINSTALL_MANTAINER"
    [ "$CROSS_COMPILER" == "yes" ] && CHECKINSTALL_FLAGS+=" --pkgarch=$CROSSTOOL_ARCH --strip=no --stripso=no"

    echo -ne "$CHECKINSTALL_SUMMARY\n" > description-pak

    checkinstall $CHECKINSTALL_FLAGS make install || return 1
}

function check_loadedConfig() {
    if [ -z "$WORKDIR" ]; then
        log_failure_msg "ERROR: config not found"
        exit 1
    fi

    WORKDIR=$(realpath "$WORKDIR")
    DLIB_SRC_FILENAME="${WORKDIR}/${DLIB_SRC_FILENAME}"
    CROSSTOOL_DIR="${WORKDIR}/toolchain/${CROSSTOOL_DIR}/"

    if [ "$CROSS_COMPILER" == "yes" ]; then
        for var in {CROSSTOOL_URL,CROSSTOOL_DIR,CROSSTOOL_NAME,CROSSTOOL_ARCH}; do
            eval "[ -z \"$"$var"\" ] && { echo log_failure_msg \"Variable $var is not set.\" ; exit 1; }"
        done
    fi

    for var in {CHECKINSTALL_INCLUDE_DOC,CHECKINSTALL_PKGNAME,CHECKINSTALL_PKGSRC,CHECKINSTALL_PKGGROUP,CHECKINSTALL_PKGALTSRC,CHECKINSTALL_MANTAINER,CHECKINSTALL_SUMMARY}; do
        eval "[ -z \"$"$var"\" ] && { echo log_failure_msg \"Variable $var is not set.\" ; exit 1; }"
    done
}

function usage() {
    echo -ne "Usage: $0 [-c|--source] [-b|--build] [-d|--check-deps] [-dw|--dw-cross-deps] [--clean] [--clean-cross-deps] [--clean-dlib-sources ]\nOptions:\t
    -c, --config                                                                 load config.
    -b. --build                                                                  do all steps, checks dependencies, download sources & toolchain (if enabled) and build debian package.
    -d, --check-deps                                                             check dlib dependencies.
    -dw,--dw-cross-deps                                                          download custom packages list for selected archtecture (cross-compilation enabled only).
                                                                                 pkg-config, includes and libraries is configured for search in cross-compilation folder, for dependencies search automatically.
                                                                                 example:
                                                                                   $0 -c <configfile> --dw-cross-deps \"libopenblas-dev:armhf\"
    --clean                                                                      clean build folder.
    --clean-cross-deps                                                           clean cross-compilation dependencies folder.
    --clean-dlib-sources                                                           clean dlib folders.
    \n"
    exit 1
}

while [ "$1" != "" ]; do
  case $1 in
    -c|--config)
      source $2 2>/dev/null || {
        log_failure_msg "couldn't load config $2"
        exit 1
      }
      shift
    ;;
    --build)
        check_loadedConfig
        install_deps || exit 1
        dw_dlib || exit 1
        dw_toolchain || exit 1
        cmakegen || exit 1
        yesnoPrompt "Do you want continue? (next steps is execute make and generates debian package) [Y/n] " || exit 0
        makedlib || exit 1
        checkinstallgen || exit 1
        exit 0
    ;;
    -d|--check-deps)
      install_deps || {
        log_failure_msg "failed on install dependences"
        exit 1
      }
    ;;
    --dw-cross-deps)
        check_loadedConfig
        [ "$CROSS_COMPILER" != "yes" ] && {
            log_failure_msg "cross compiler is disabled."
            exit 1
        }
        fetch_cross_local_deps "$2"
        exit 0
    ;;
    --clean)
        check_loadedConfig
        rm -rf ${WORKDIR}/dlib-${DLIB_VERSION}/build/ &>/dev/null
        rm -rf ${WORKDIR}/dlib-${DLIB_VERSION}/tools/python/build/ &>/dev/null
        log_app_msg "build folder was removed."
        exit 0
    ;;
    --clean-cross-deps)
        check_loadedConfig
        [ -z "$CROSSTOOL_ARCH" ] && {
            log_failure_msg "cross compiler is disabled."
            exit 1
        }
        rm -rf ${WORKDIR}/cross_deps/deps/${CROSSTOOL_ARCH}/
        rm -rf ${WORKDIR}/cross_deps/debs/${CROSSTOOL_ARCH}/
        log_app_msg "dependencies folder was removed."
        exit 0
    ;;
    --clean-dlib-sources)
        check_loadedConfig
        rm -rf ${WORKDIR}/dlib-${DLIB_VERSION}/
        log_app_msg "dlib folder was removed."
        exit 0
    ;;
    *)
        usage
    ;;
  esac
  shift
done
