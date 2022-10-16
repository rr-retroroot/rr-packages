#!/bin/bash

set -e

RR_SSH_HOST="us.mydedibox.fr"
RR_SSH_HOST_MIRROR="mydedibox.fr"

COL_R='\033[0;31m'
COL_G='\033[0;32m'
COL_Y='\033[0;33m'
COL_N='\033[0m'

# cleanup on exit
function cleanup {
  if [ $? -ne 0 ]; then
    echo "${COL_R}something went wrong...\n${COL_N}"
  fi
  rm -rf rr-repo-x86_64
  rm -rf rr-repo-armv7h
  rm -rf rr-repo-aarch64
  rm -rf rr-repo-toolchain
}

# set exit trap
trap cleanup EXIT

function die() {
  printf "${COL_R}ERR: %s\n${COL_N}" "$@" 1>&2
	exit $retval
}

function pacman_sync() {
  echo -e "${COL_G}pacman_sync:${COL_N} synching repositories..."
  sudo pacbrew-pacman --config pacman.conf -Syy &> /dev/null || die "pacman_sync: repo sync failed"
  #sudo pacbrew-pacman --config pacman.conf -S --noconfirm --needed rr-toolchain || die "pacman_sync: rr-toolchain installation failed"
  echo -e "${COL_G}pacman_sync:${COL_N} ok"
}

function download_repos() {
  echo -e "${COL_G}download_repos:${COL_N} downloading retroroot repos..."
  rm -rf rr-repo-x86_64 && mkdir -p rr-repo-x86_64
  rm -rf rr-repo-armv7h && mkdir -p rr-repo-armv7h
  rm -rf rr-repo-aarch64 && mkdir -p rr-repo-aarch64
  rm -rf rr-repo-toolchain && mkdir -p rr-repo-toolchain
  scp "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/x86_64/retroroot-*.*" rr-repo-x86_64 || die "download_repos: repo download error"
  scp "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/armv7h/retroroot-*.*" rr-repo-armv7h || die "download_repos: repo download error"
  scp "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/aarch64/retroroot-*.*" rr-repo-aarch64 || die "download_repos: repo download error"
  scp "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/toolchain/retroroot-*.*" rr-repo-toolchain || die "download_repos: repo download error"
}

function upload_repos() {
  echo -e "${COL_G}upload_repos:${COL_N} uploading retroroot repos..."
  scp rr-repo-x86_64/* "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/x86_64/" || die "upload_repos: repo upload error"
  scp rr-repo-armv7h/* "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/armv7h/" || die "upload_repos: repo upload error"
  scp rr-repo-aarch64/* "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/aarch64/" || die "upload_repos: repo upload error"
  scp rr-repo-toolchain/* "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/toolchain/" || die "upload_repos: repo upload error"
}

# upload_pkg PKGNAME PKGPATH ARCH
function upload_app_pkg() {
  local pkgname=$1
  local pkgpath=$2
  local pkgarch=$3
  echo -e "${COL_G}upload_app_pkg:${COL_N} uploading ${COL_G}$pkgname${COL_N} ($pkgarch) to retroroot repos"
  scp "$pkgpath/"*-$pkgarch.pkg.tar.xz "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/$pkgarch" || die "upload_app_pkg: scp to $RR_SSH_HOST failed"
  pacbrew-repo-add "rr-repo-$pkgarch/retroroot-$pkgarch.db.tar.gz" "$pkgpath/"*-$pkgarch.pkg.tar.xz || die "upload_app_pkg: repo-add failed"
}

# upload_pkg PKGNAME PKGPATH
function upload_toolchain_pkg() {
  local pkgname=$1
  local pkgpath=$2
  echo -e "${COL_G}upload_toolchain_pkg:${COL_N} uploading ${COL_G}$pkgname${COL_N} to retroroot repos"
  scp "$pkgpath/"*.pkg.tar.xz "$RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/toolchain" || die "upload_toolchain_pkg: scp to $RR_SSH_HOST failed"
  pacbrew-repo-add "rr-repo-toolchain/retroroot-toolchain.db.tar.gz" "$pkgpath/"*.pkg.tar.xz || die "upload_toolchain_pkg: repo-add failed"
}

# is_toolchain_pkg PKGBUILD
function is_toolchain_pkg() {
  local groups=`cat "$1" | grep "groups=" | sed -n "s/^.*(\(.*\)).*$/\1/ p"`
  if [[ "$groups" == *"rr-toolchain"* ]]; then
    # 0 = true
    return 0 
  else
    # 1 = false
    return 1
  fi
}

# get_local_pkg_arch PKGBUILD
function get_local_pkg_arch() {
  local arch=`cat "$1" | grep "arch=" | sed -n "s/^.*(\(.*\)).*$/\1/ p"`
  echo "$arch"
}

# get_local_pkg_version PKGBUILD
function get_local_pkg_ver() {
  local local_pkgver=`cat "$1" | grep "pkgver=" | sed 's/pkgver=//g'`
  local local_pkgrel=`cat "$1" | grep "pkgrel=" | sed 's/pkgrel=//g'`
  echo "$local_pkgver-$local_pkgrel"
}

# get_remote_pkg_version ARCH PKGNAME
function get_remote_pkg_ver() {
  local remote_pkgname=$(echo "$RR_REMOTE_PACKAGES" | grep "retroroot-$1" | grep -E "(^| )$2( |$)" | awk '{print $2}')
  local remote_pkgverrel=$(echo "$RR_REMOTE_PACKAGES" | grep "retroroot-$1" | grep -E "(^| )$2( |$)" | awk '{print $3}')
  if [ -z "$remote_pkgverrel" ]; then
    remote_pkgverrel="n/a"
  fi
  echo "$remote_pkgverrel"
}

function build_package() {
  # build package
  pushd "$1" &> /dev/null || die "build_package: pushd $1 failed"
  rm -rf *.pkg.tar.* &> /dev/null
  # -d: we don't want to install deps ("cross-compilation")
  CARCH=$2 pacbrew-makepkg -Cfd || die "build_package: makepkg failed"
  if [ $3 ]; then
    echo -e "${COL_G}build_package:${COL_N} installing ${COL_G}$pkgname${COL_N} ($local_pkgver)..."
    sudo pacbrew-pacman --noconfirm -U *.pkg.tar.* || die "build_package: pkg installation failed"
  fi
  popd &> /dev/null || die "build_package: popd failed"
}

function rr_build() {
  # sync pacman packages
  pacman_sync
  
  # get remote package list
  RR_REMOTE_PACKAGES=$(pacbrew-pacman --config pacman.conf -Sl)
  RR_BUILD_PATH="."

  # parse args
  while test $# -gt 0
  do
    case "$1" in
      -a) shift && RR_BUILD_ARCH="$1"
          echo -e "${COL_G}rr_build${COL_N}: forced arch (${COL_Y}$RR_BUILD_ARCH${COL_N})"
        ;;
      -f) echo -e "${COL_G}rr_build${COL_N}: force rebuild all packages enabled"
          RR_BUILD_ALL=true
        ;;
      -h) RR_UPLOAD=true
          shift && RR_SSH_HOST="$1"
          echo -e "${COL_G}rr_build${COL_N}: uploading packages to retroroot repos with specified host ($RR_SSH_HOST)"
        ;;
      -i) echo -e "${COL_G}rr_build${COL_N}: install built packages"
          RR_INSTALL=true
        ;;
      -p) shift && RR_BUILD_PATH="$1/"
          echo -e "${COL_G}rr_build${COL_N}: building packages in specified path: ${RR_BUILD_PATH}"
        ;;
      -u) RR_UPLOAD=true
          shift && RR_SSH_USER="$1"
          echo -e "${COL_G}rr_build${COL_N}: uploading packages to retroroot repos with specified user ($RR_SSH_USER)"
        ;;
    esac
    shift
  done
  
  # download repository files
  if [ $RR_UPLOAD ]; then
    download_repos
  fi

  # loop through packages, ignore "pkg" and "src"
  pkgs=$(find "${RR_BUILD_PATH}" \( -path "*/pkg" -o -path "*/src" \) -prune -o -name PKGBUILD -print)
  for pkg in $pkgs; do
    # get pkgbuild basename
    local pkgpath=$(dirname "$pkg")
    # get local package name and version
    local pkgname=$(cat "$pkg" | grep "pkgname=" | sed 's/pkgname=//g')
    local local_pkgver=$(get_local_pkg_ver "$pkg")
    #echo "pkg: $pkg, path: $pkgpath"

    # build a "host" "toolchain" package
    if is_toolchain_pkg "$pkg"; then
      local remote_pkgver=$(get_remote_pkg_ver "toolchain" "$pkgname")
      # only build packages if force requested (-f) or local/remote pkg versions differ
      if [ $RR_BUILD_ALL ] || [ "$local_pkgver" != "$remote_pkgver" ]; then
        echo -e "${COL_G}rr_build:${COL_N} new package: ${COL_G}$pkgname${COL_N} (${COL_Y}x86_64${COL_N}) ($remote_pkgver => $local_pkgver)"
        echo -e "${COL_G}rr_build:${COL_N} building ${COL_G}$pkgname${COL_N} (${COL_Y}x86_64${COL_N}) ($local_pkgver)"
        build_package "$pkgpath" "x86_64" $RR_INSTALL
        if [ $RR_UPLOAD ]; then
          upload_toolchain_pkg "$pkgname" "$pkgpath"
        fi
      else
        # package is up to date
        echo -e "${COL_G}rr_build: $pkgname${COL_N} (${COL_Y}x86_64${COL_N}) is up to date ($remote_pkgver => $local_pkgver)..."
      fi
    else
      # build a "target" package
      if [ -z ${RR_BUILD_ARCH+x} ]; then
        ARCHS="x86_64 armv7h aarch64"
      else
        ARCHS="$RR_BUILD_ARCH"
      fi
      for ARCH in ${ARCHS}; do
        # skip package if it's not for current arch
        local pkgarch=$(get_local_pkg_arch "$pkg")
        if [[ "$pkgarch" != *"$ARCH"* ]] && [[ "$pkgarch" != *"any"* ]]; then
          echo -e "${COL_G}rr_build:${COL_N} ${COL_G}$pkgname${COL_N} (${COL_Y}${ARCH}${COL_N}) was skipped (pkg arch: ${COL_Y}$pkgarch${COL_N})"
          continue
        fi
        
        # only build packages if force requested (-f) or local/remote pkg versions differ
        local remote_pkgver=$(get_remote_pkg_ver "${ARCH}" "$pkgname")
        if [ $RR_BUILD_ALL ] || [ "$local_pkgver" != "$remote_pkgver" ]; then
          echo -e "${COL_G}rr_build:${COL_N} new package: ${COL_G}$pkgname${COL_N} (${COL_Y}${ARCH}${COL_N}) ($remote_pkgver => $local_pkgver)"
          echo -e "${COL_G}rr_build:${COL_N} building ${COL_G}$pkgname${COL_N} (${COL_Y}${ARCH}${COL_N}) ($local_pkgver)"
          build_package "$pkgpath" "${ARCH}" $RR_INSTALL
          if [ $RR_UPLOAD ]; then
            upload_app_pkg "$pkgname" "$pkgpath" "${ARCH}"
          fi
          echo -e "${COL_G}rr_build:${COL_N} build sucess for ${COL_G}$pkgpath/$pkgname-$local_pkgver.pkg.tar.xz${COL_N}"
        else
          # package is up to date
          echo -e "${COL_G}rr_build: $pkgname${COL_N} (${COL_Y}${ARCH}${COL_N}) is up to date ($remote_pkgver => $local_pkgver)..."
        fi
      done
    fi
  done

  # upload updated repos files and cleanup
  if [ $RR_UPLOAD ]; then
    upload_repos
  fi

  echo -e "${COL_G}rr_build:${COL_N} all done !"
}

rr_build "$@"

