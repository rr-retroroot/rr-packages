#!/bin/bash

set -e

COL_RED='\033[0;31m'
COL_GREEN='\033[0;32m'
COL_NONE='\033[0m'

function die() {
  printf "${COL_RED}ERR: %s\n${COL_NONE}" "$@" 1>&2
	exit $retval
}

function check_pacman {
  echo -e "${COL_GREEN}check_pacman:${COL_NONE} synching repositories..."
  sudo pacbrew-pacman -Syy &> /dev/null || die "check_pacman: repo sync failed"
  echo -e "${COL_GREEN}check_pacman:${COL_NONE} ok"
}

function build_package {
  # build package
  pushd "$1" &> /dev/null || die "build_package: pushd $1 failed"
  rm -rf *.pkg.tar.xz &> /dev/null
  # -d: we don't want to install deps ("cross-make")
  CARCH=${RR_ARCH} pacbrew-makepkg -C -f -d || die "build_package: makepkg failed"
  popd &> /dev/null || die "build_package: popd failed"
}

function build_packages {
  RR_ARCH=x86_64
  RR_SSH_HOST="us.mydedibox.fr"
  RR_SSH_HOST_MIRROR="mydedibox.fr"
  RR_SSH_PATH="packages/apps/${RR_ARCH}"
  RR_REPO_PATH="rr-repo-${RR_ARCH}"
  RR_REPO_FILE="retroroot-${RR_ARCH}.db.tar.gz"
  RR_LOCAL_PATH="packages"
  RR_BUILD_TOOLCHAIN=false
  REMOTE_PACKAGES=`pacbrew-pacman -Sl`

  # parse args
  while test $# -gt 0
  do
    case "$1" in
      -a) shift && RR_ARCH="$1"
          RR_SSH_PATH="packages/apps/${RR_ARCH}"
          RR_REPO_PATH="rr-repo-${RR_ARCH}"
          RR_REPO_FILE="retroroot-${RR_ARCH}.db.tar.gz"
          RR_BUILD_TOOLCHAIN=false
        ;;
      -f) echo -e "${COL_GREEN}build_packages${COL_NONE}: force rebuild all packages"
          RR_BUILD_ALL=true
        ;;
      -t) echo -e "${COL_GREEN}build_packages${COL_NONE}: building toolchain"
          RR_BUILD_TOOLCHAIN=true
          RR_SSH_PATH="packages/toolchain"
          RR_LOCAL_PATH="toolchain"
          RR_REPO_PATH="rr-repo-toolchain"
          RR_REPO_FILE="retroroot-toolchain.db.tar.gz"
          RR_ARCH=
        ;;
      -u) echo -e "${COL_GREEN}build_packages${COL_NONE}: uploading packages to retroroot repos with specified user"
          RR_UPLOAD=true
          shift && RR_SSH_USER="$1"
        ;;
      -h) echo -e "${COL_GREEN}build_packages${COL_NONE}: uploading packages to retroroot repos with specified host"
          RR_UPLOAD=true
          shift && RR_SSH_HOST="$1"
        ;;
    esac
    shift
  done
  
  echo -e "${COL_GREEN}build_packages${COL_NONE}: buidling packages for \"$RR_ARCH\" arch, repo path: \"${RR_SSH_PATH}\""
  
  # download repo files from server, if needed
  if [ $RR_UPLOAD ]; then
    echo -e "${COL_GREEN}build_packages:${COL_NONE} downloading retroroot repo..."
    rm -rf ${RR_REPO_PATH} && mkdir -p ${RR_REPO_PATH}
    scp $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/${RR_SSH_PATH}/retroroot-*.* ${RR_REPO_PATH} || die "build_packages: repo download error"
  fi

  shopt -s globstar
  for pkg in ${RR_LOCAL_PATH}/**/PKGBUILD; do
    # get basename
    pkgpath=$(dirname "$pkg")

    # get local package name and version
    local_pkgname=`cat $pkgpath/PKGBUILD | grep pkgname= | sed 's/pkgname=//g'`
    local_pkgver=`cat $pkgpath/PKGBUILD | grep pkgver= | sed 's/pkgver=//g'`
    local_pkgrel=`cat $pkgpath/PKGBUILD | grep pkgrel= | sed 's/pkgrel=//g'`
    local_pkgverrel="$local_pkgver-$local_pkgrel"

    # get remote package name and version
    remote_pkgname=`echo "$REMOTE_PACKAGES" | grep retroroot-${RR_ARCH} | grep -E "(^| )$local_pkgname( |$)" | awk '{print $2}'`
    remote_pkgverrel=`echo "$REMOTE_PACKAGES" | grep retroroot-${RR_ARCH} | grep -E "(^| )$local_pkgname( |$)" | awk '{print $3}'`
    if [ -z "$remote_pkgverrel" ]; then
      remote_pkgverrel="n/a"
    fi

    # only build packages that are not available (version differ)
    if [ $RR_BUILD_ALL ] || [ "$local_pkgverrel" != "$remote_pkgverrel" ]; then
      echo -e "${COL_GREEN}build_packages:${COL_NONE} new package: ${COL_GREEN}$local_pkgname${COL_NONE} ($remote_pkgverrel => $local_pkgverrel)"
      echo -e "${COL_GREEN}build_packages:${COL_NONE} building ${COL_GREEN}$local_pkgname${COL_NONE} ($local_pkgverrel)"
      build_package "$pkgpath"
      echo -e "${COL_GREEN}build_packages:${COL_NONE} build sucess for ${COL_GREEN}$pkgpath/$local_pkgname-$local_pkgverrel.pkg.tar.xz${COL_NONE}"
      if [ $RR_UPLOAD ]; then
        echo -e "${COL_GREEN}build_packages:${COL_NONE} uploading ${COL_GREEN}$local_pkgname${COL_NONE} to retroroot repos"
        scp $pkgpath/*.pkg.tar.xz $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/${RR_SSH_PATH}/ || die "build_packages: scp to $RR_SSH_HOST failed"
        #scp $pkgpath/*.pkg.tar.xz $RR_SSH_USER@$RR_SSH_HOST_MIRROR:/var/www/retroroot/${RR_SSH_PATH}/ || die "build_packages: scp to $RR_SSH_HOST_MIRROR failed"
        pacbrew-repo-add ${RR_REPO_PATH}/${RR_REPO_FILE} $pkgpath/*.pkg.tar.xz || die "build_packages: repo-add failed"
      fi
    else
      # package is up to date
      echo -e "${COL_GREEN}build_packages: $local_pkgname${COL_NONE} is up to date ($remote_pkgverrel => $local_pkgverrel)..."
    fi
  done

  # upload updated repos files and cleanup
  if [ $RR_UPLOAD ]; then
    echo -e "${COL_GREEN}build_packages:${COL_NONE} updating retroroot repos with new packages..."
    scp ${RR_REPO_PATH}/* $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/${RR_SSH_PATH}/ || die "build_packages: scp to $RR_SSH_HOST failed"
    #scp ${RR_REPO_PATH}/* $RR_SSH_USER@$RR_SSH_HOST_MIRROR:/var/www/retroroot/${RR_SSH_PATH}/ || die "build_packages: scp to $RR_SSH_HOST_MIRROR failed"
    rm -rf ${RR_REPO_PATH}
  fi

  echo -e "${COL_GREEN}build_packages:${COL_NONE} all done !"
}

check_pacman
build_packages "$@"

