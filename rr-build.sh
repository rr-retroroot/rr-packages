#!/bin/bash

set -e

ARCH=x86_64
REPO_PATH=rr-repo

COL_GREEN='\033[0;32m'
COL_NONE='\033[0m'

function check_pacman {
  echo -e "${COL_GREEN}check_pacman:${COL_NONE} synching repositories..."
  sudo pacman -Syy &> /dev/null
  echo -e "${COL_GREEN}check_pacman:${COL_NONE} ok"
}

function install_local_package {
  sudo pacman --noconfirm -U $1 &> /dev/null || exit 1
}

function install_remote_package {
  sudo pacman --noconfirm --needed -S $1 &> /dev/null || exit 1
}

function build_package {
  # build package
  pushd "$1" &> /dev/null || exit 1
  rm -rf *.pkg.tar.zst &> /dev/null || exit 1
  # -s: we don't want to install deps that are not available in retroroot image, so fail if deps are not installed
  makepkg -C -f -s || exit 1
  popd &> /dev/null || exit 1
}

function build_packages {
  RR_SSH_HOST="us.mydedibox.fr"
  remote_packages=`pacman -Sl`

  # parse args
  while test $# -gt 0
  do
    case "$1" in
      -f) echo -e "${COL_GREEN}build_packages${COL_NONE}: force rebuild all packages"
          RR_BUILD_ALL=true
        ;;
      -u) echo -e "${COL_GREEN}build_packages${COL_NONE}: uploading packages to retroroot repo with specified user"
          RR_UPLOAD=true
          shift && RR_SSH_USER="$1"
        ;;
      -h) echo -e "${COL_GREEN}build_packages${COL_NONE}: uploading packages to retroroot repo with specified host"
          RR_UPLOAD=true
          shift && RR_SSH_HOST="$1"
        ;;
    esac
    shift
  done

  # download repo files from server, if needed
  if [ $RR_UPLOAD ]; then
    echo -e "${COL_GREEN}build_packages:${COL_NONE} downloading retroroot repo..."
    rm -rf ${REPO_PATH} && mkdir -p ${REPO_PATH}
    scp $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/${ARCH}/retroroot.* ${REPO_PATH} || exit 1
  fi

  while read line; do
    # skip empty lines and comments
    if [ -z "$line" ] || [[ $line == \#* ]] ; then
      continue
    fi

    # get local package name and version
    local_pkgname=`cat $line/PKGBUILD | grep pkgname= | sed 's/pkgname=//g'`
    local_pkgver=`cat $line/PKGBUILD | grep pkgver= | sed 's/pkgver=//g'`
    local_pkgrel=`cat $line/PKGBUILD | grep pkgrel= | sed 's/pkgrel=//g'`
    local_pkgverrel="$local_pkgver-$local_pkgrel"

    # get remote package name and version
    remote_pkgname=`echo "$remote_packages" | grep -E "(^| )$local_pkgname( |$)" | awk '{print $2}'`
    remote_pkgverrel=`echo "$remote_packages" | grep -E "(^| )$local_pkgname( |$)" | awk '{print $3}'`
    if [ -z "$remote_pkgverrel" ]; then
      remote_pkgverrel="n/a"
    fi

    # only build packages that are not available (version differ)
    if [ $RR_BUILD_ALL ] || [ "$local_pkgverrel" != "$remote_pkgverrel" ]; then
      echo -e "${COL_GREEN}build_packages:${COL_NONE} new package: ${COL_GREEN}$local_pkgname${COL_NONE} ($remote_pkgverrel => $local_pkgverrel)"
      echo -e "${COL_GREEN}build_packages:${COL_NONE} building ${COL_GREEN}$local_pkgname${COL_NONE} ($local_pkgverrel)"
      build_package "$line"
      echo -e "${COL_GREEN}build_packages:${COL_NONE} build sucess for ${COL_GREEN}$line/$local_pkgname-$local_pkgverrel.pkg.tar.zst${COL_NONE}"
      if [ $RR_UPLOAD ]; then
        echo -e "${COL_GREEN}build_packages:${COL_NONE} uploading ${COL_GREEN}$local_pkgname${COL_NONE} to retroroot repo"
        scp $line/*.pkg.tar.zst $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/${ARCH}/ || exit 1
        repo-add ${REPO_PATH}/retroroot.db.tar.gz $line/*.pkg.tar.zst || exit 1
      fi
    else
      # package is up to date
      echo -e "${COL_GREEN}build_packages: $local_pkgname${COL_NONE} is up to date ($remote_pkgverrel => $local_pkgverrel)..."
    fi

  done < rr-packages-${ARCH}.cfg

  # upload updated repo files and cleanup
  if [ $RR_UPLOAD ]; then
    echo -e "${COL_GREEN}build_packages:${COL_NONE} updating retroroot repo with new packages..."
    scp ${REPO_PATH}/* $RR_SSH_USER@$RR_SSH_HOST:/var/www/retroroot/packages/${ARCH}/ || exit 1
    rm -rf ${REPO_PATH}
  fi

  echo -e "${COL_GREEN}build_packages:${COL_NONE} all done !"
}

check_pacman
build_packages "$@"

