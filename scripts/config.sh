#!/bin/bash

# scripts root directory
SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"
# output directory
BUILDDIR="/build"
# jdk repository directory
JDKDIR="$BUILDDIR/jdk"
# openjdk-build repo dir
ABLDDIR="$BUILDDIR/openjdk-build"
# openjdk-build repo
ABLDREPO="https://github.com/AdoptOpenJDK/openjdk-build.git"
# cacertfile
CACERTFILE="$ABLDDIR/security/cacerts"
# hg tarball
JAVA_TMP="$BUILDDIR/jdk_tmp"
TARBALL_MAX_DOWNLOADS=10

JRI_MODULES="java.se,jdk.jdwp.agent,jdk.unsupported,jdk.management.agent,jdk.jartool,jdk.crypto.ec"

JTREG="$BUILDDIR/jtreg"
JTREG_URL="https://ci.adoptopenjdk.net/view/Dependencies/job/jtreg/lastSuccessfulBuild/artifact/jtreg-4.2.0-tip.tar.gz"
JTREG_FILE="$BUILDDIR/jtreg.tar.gz"

###############################################################################
# Set the debug level
#    release: no debug information, all optimizations, no asserts.
#    optimized: no debug information, all optimizations, no asserts, HotSpot target is 'optimized'.
#    fastdebug: debug information (-g), all optimizations, all asserts
#    slowdebug: debug information (-g), no optimizations, all asserts
if [ "$JDKDEBUG" == "release" ] ||
   [ "$JDKDEBUG" == "optimized" ] ||
   [ "$JDKDEBUG" == "fastdebug" ] ||
   [ "$JDKDEBUG" == "slowdebug" ]; then
  HOTSPOT_DEBUG="$JDKDEBUG"
elif [ -z "$JDKDEBUG" ]; then
  HOTSPOT_DEBUG="release"
else
  echo "Error! Please specify a valid JVM debug level via the JDKDEBUG environment variable." >&2
  echo "Acceptable values:" >&2
  echo "JDKDEBUG=release" >&2
  echo "JDKDEBUG=optimized" >&2
  echo "JDKDEBUG=fastdebug" >&2
  echo "JDKDEBUG=slowdebug" >&2
  exit 1
fi


# EV3
if [ "$JDKPLATFORM" == "ev3" ]; then
  eval "$(dpkg-architecture -s -a armel -A armel)"

# invalid or unset platform
else
  echo "Error! Please specify JDK platform to compile via the JDKPLATFORM environment variable." >&2
  echo "Acceptable values:" >&2
  echo "JDKPLATFORM=ev3" >&2
  exit 1
fi

##
## Version-specific configuration
##

# invalid or unset VM
if [ "$JDKVM" != "zero" ] && [ "$JDKVM" != "client" ] && [ "$JDKVM" != "minimal" ] && [ "$JDKVM" != "custom" ]; then
  echo "Error! Please specify JDK VM to compile via the JDKVM environment variable." >&2
  echo "Acceptable values:" >&2
  echo "JDKVM=client" >&2
  echo "JDKVM=minimal" >&2
  echo "JDKVM=zero" >&2
  echo "JDKVM=custom" >&2
  exit 1
fi

HOTSPOT_VARIANT="--with-jvm-variants=$JDKVM"
if [ "$JDKVM" = "minimal" ]; then
  # link-time-opt is automatic on minimal for ARM, see /make/autoconf/hotspot.m4
  HOTSPOT_VARIANT="$HOTSPOT_VARIANT --with-jvm-features=minimal,compiler1,serialgc,cds,jvmti,services,link-time-opt --disable-dtrace"
  if [ "$HOTSPOT_DEBUG" = "slowdebug" ]; then
    echo "[CONFIGURATION] WARNING: minimal doesn't properly generate all debug symbols." >&2
  fi
elif [ "$JDKVM" = "custom" ]; then
  if [ "$HOTSPOT_DEBUG" = "release" ]; then
    HOTSPOT_VARIANT="$HOTSPOT_VARIANT --with-jvm-features=cds,compiler1,jfr,g1gc,jvmti,management,nmt,serialgc,services,vm-structs,link-time-opt"
  else
    HOTSPOT_VARIANT="$HOTSPOT_VARIANT --with-jvm-features=cds,compiler1,jfr,g1gc,jvmti,management,nmt,serialgc,services,vm-structs"
  fi
elif [ "$JDKVM" = "client" ]; then
  if [ "$HOTSPOT_DEBUG" = "release" ]; then
    echo "a" >/dev/null
    #if [ "$JDKVER" -gt 11 ]; then
    #  HOTSPOT_VARIANT="$HOTSPOT_VARIANT --with-jvm-features=link-time-opt"
    #fi
  else
    HOTSPOT_VARIANT="$HOTSPOT_VARIANT"
  fi
fi

VENDOR_FLAGS="              --with-vendor-name=ev3dev-lang-java "
VENDOR_FLAGS="$VENDOR_FLAGS --with-vendor-url=https://github.com/ev3dev-lang-java/ev3dev-lang-java/ "
VENDOR_FLAGS="$VENDOR_FLAGS --with-vendor-bug-url=https://github.com/ev3dev-lang-java/ev3dev-lang-java/issues/new "
VENDOR_FLAGS="$VENDOR_FLAGS --with-vendor-vm-bug-url=https://github.com/ev3dev-lang-java/ev3dev-lang-java/issues/new "

# output images directory
#IMAGEDIR="/build/jdk/build/linux-arm-normal-client-release/images"

# mercurial repository
#JAVA_REPO="http://hg.openjdk.java.net/jdk-updates/jdkXu/"

# patch to apply
#PATCHVER="jdkX"

# path to autogen.sh to regenerate the build system
#AUTOGEN_PATH="./common/autoconf/autogen.sh"

# hotspot variant to use
#HOTSPOT_VARIANT=client
# A comment from OpenJDK build system sums it up pretty well:
##   server: normal interpreter, and a tiered C1/C2 compiler
##   client: normal interpreter, and C1 (no C2 compiler)
##   minimal: reduced form of client with optional features stripped out
##   core: normal interpreter only, no compiler
##   zero: C++ based interpreter only, no compiler
##   custom: baseline JVM with no default features
# 'client' JVM starts fast enough and provides the best performance.
# 'zero' JVM provides us with a fallback when ARMv5 sflt JIT stops working completely.

## Boot JDK configs

# Destination Boot JDK directory
#HOSTJDK="$BUILDDIR/jdk-9.0.4"

# Cached archive
#HOSTJDK_FILE="$BUILDDIR/openjdk-9.0.4.tar.gz"

# Download URL
#HOSTJDK_URL="https://download.java.net/java/GA/jdk9/9.0.4/binaries/openjdk-9.0.4_linux-x64_bin.tar.gz"

# OpenJDK 9
if [ "$JDKVER" == "9" ]; then
  VERSION_POLICY="jdk-9.0.4+11"
  JAVA_SCM="git"
  JAVA_REPO="https://github.com/AdoptOpenJDK/openjdk-jdk9u.git"
  PATCHVER="jdk9"
  AUTOGEN_STYLE="v1"
  AUTOGEN_PATH="./common/autoconf/autogen.sh"
  if [ "$BUILDER_TYPE" = "native" ]; then
    echo "Error: native builds are not supported for JDK9." >&2
    exit 1
  else
    # same for both stretch & buster
    # JDK8 is still supported, so let's use that as we can
    HOSTJDK="$BUILDDIR/jdk8u222-b10"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK8U-jdk_x64_linux_hotspot_8u222b10.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u222-b10/OpenJDK8U-jdk_x64_linux_hotspot_8u222b10.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-normal-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm926ejs
  JNI_PATH_FLAGS=
  VENDOR_FLAGS=

# OpenJDK 10
elif [ "$JDKVER" == "10" ]; then
  VERSION_POLICY="jdk-10.0.2+13"
  JAVA_SCM="git"
  JAVA_REPO="https://github.com/AdoptOpenJDK/openjdk-jdk10u.git"
  PATCHVER="jdk10"
  AUTOGEN_STYLE="v1"
  AUTOGEN_PATH="./make/autoconf/autogen.sh"
  if [ "$BUILDER_TYPE" = "native" ]; then
    echo "Error: native builds are not supported for JDK10." >&2
    exit 1
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-10.0.2+13"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK10_x64_Linux_jdk-10.0.2+13.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk10-releases/releases/download/jdk-10.0.2%2B13/OpenJDK10_x64_Linux_jdk-10.0.2%2B13.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-normal-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm926ejs
  JNI_PATH_FLAGS=

# OpenJDK 11
elif [ "$JDKVER" == "11" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_SCM="git"
  JAVA_REPO="https://github.com/openjdk/jdk11u.git"
  PATCHVER="jdk11"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-11/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-11/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-11.0.4+11"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK11U-jdk_x64_linux_hotspot_11.0.4_11.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.4%2B11/OpenJDK11U-jdk_x64_linux_hotspot_11.0.4_11.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-normal-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm926ejs
  JNI_PATH_FLAGS=

# OpenJDK 12
elif [ "$JDKVER" == "12" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_SCM="git"
  JAVA_REPO="https://github.com/openjdk/jdk12u.git"
  PATCHVER="jdk12"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-11/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-11/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-11.0.4+11"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK11U-jdk_x64_linux_hotspot_11.0.4_11.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.4%2B11/OpenJDK11U-jdk_x64_linux_hotspot_11.0.4_11.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# OpenJDK 13
elif [ "$JDKVER" == "13" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_SCM="git"
  JAVA_REPO="https://github.com/openjdk/jdk13u.git"
  PATCHVER="jdk13"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-12/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-12/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-12.0.2+10"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK12U-jdk_x64_linux_hotspot_12.0.2_10.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk12-binaries/releases/download/jdk-12.0.2%2B10/OpenJDK12U-jdk_x64_linux_hotspot_12.0.2_10.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# OpenJDK 14
elif [ "$JDKVER" == "14" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_REPO="https://github.com/openjdk/jdk14u.git"
  JAVA_SCM="git"
  PATCHVER="jdk14"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-13/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-13/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-13+33"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK13U-jdk_x64_linux_hotspot_13_33.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk13-binaries/releases/download/jdk-13%2B33/OpenJDK13U-jdk_x64_linux_hotspot_13_33.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# OpenJDK 15
elif [ "$JDKVER" == "15" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_REPO="https://github.com/openjdk/jdk15u.git"
  JAVA_SCM="git"
  PATCHVER="jdk15"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-15/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-15/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-15.0.1+9"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK15U-jdk_x64_linux_hotspot_15.0.1_9.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk15-binaries/releases/download/jdk-15.0.1%2B9/OpenJDK15U-jdk_x64_linux_hotspot_15.0.1_9.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# OpenJDK 16
elif [ "$JDKVER" == "16" ]; then
  VERSION_POLICY="latest_general_availability"
  JAVA_REPO="https://github.com/openjdk/jdk16u.git"
  JAVA_SCM="git"
  PATCHVER="jdk16"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-16/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-16/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-16.0.2+7"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK16U-jdk_x64_linux_hotspot_16.0.2_7.tar.gz"
    HOSTJDK_URL="https://github.com/adoptium/temurin16-binaries/releases/download/jdk-16.0.2%2B7/OpenJDK16U-jdk_x64_linux_hotspot_16.0.2_7.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# OpenJDK Loom & Master+dev
elif [ "$JDKVER" == "loom" ] || [ "$JDKVER" == "tip" ]; then
  if [ "$JDKVER" == "loom" ]; then
    VERSION_POLICY="latest_commit"
    VERSION_SUFFIX="ev3-loom-experimental"
    JAVA_REPO="https://github.com/openjdk/loom.git"
    JAVA_BRANCH="fibers"
    PATCHVER="loom"
  else
    VERSION_POLICY="latest_tag"
    JAVA_REPO="https://github.com/openjdk/jdk.git"
    PATCHVER="jdk16"
  fi
  JAVA_SCM="git"
  AUTOGEN_STYLE="v2"
  if [ "$BUILDER_TYPE" = "native" ]; then
    HOSTJDK="$BUILDDIR/jdk-ev3"
    HOSTJDK_RENAME_FROM="$BUILDDIR/jdk"
    HOSTJDK_FILE="$BUILDDIR/jdk-ev3.tar.gz"
    # stretch and buster have different versions
    if [ "$BUILDER_DISTRO" = "stretch" ]; then
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/stretch-15/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    else
      HOSTJDK_URL="https://ci.adoptopenjdk.net/job/eljbuild/job/buster-15/lastSuccessfulBuild/artifact/build/jdk-ev3.tar.gz"
    fi
  else
    # same for both stretch & buster
    HOSTJDK="$BUILDDIR/jdk-15.0.1+9"
    HOSTJDK_FILE="$BUILDDIR/OpenJDK15U-jdk_x64_linux_hotspot_15.0.1_9.tar.gz"
    HOSTJDK_URL="https://github.com/AdoptOpenJDK/openjdk15-binaries/releases/download/jdk-15.0.1%2B9/OpenJDK15U-jdk_x64_linux_hotspot_15.0.1_9.tar.gz"
  fi
  IMAGEDIR="$JDKDIR/build/linux-arm-${JDKVM}-${HOTSPOT_DEBUG}/images"
  HOTSPOT_ABI=arm-sflt
  JNI_PATH_FLAGS="--with-jni-libpath=/usr/lib/$DEB_HOST_MULTIARCH/jni:/lib/$DEB_HOST_MULTIARCH:/usr/lib/$DEB_HOST_MULTIARCH:/usr/lib/jni:/lib:/usr/lib"

# invalid or unset version
else
  echo "Error! Please specify JDK version to compile via the JDKVER environment variable." >&2
  echo "Acceptable values:" >&2
  echo "JDKVER=9" >&2
  echo "JDKVER=10" >&2
  echo "JDKVER=11" >&2
  echo "JDKVER=12" >&2
  echo "JDKVER=13" >&2
  echo "JDKVER=14" >&2
  echo "JDKVER=15" >&2
  echo "JDKVER=loom" >&2
  echo "JDKVER=tip" >&2
  exit 1
fi

if [ -z "$BUILDER_TYPE" ] || [ "$BUILDER_TYPE" = "cross" ]; then
  AR=arm-linux-gnueabi-gcc-ar
  NM=arm-linux-gnueabi-gcc-nm
  TARGET_FLAGS="--openjdk-target=arm-linux-gnueabi"
  BOOTCYCLE=no
elif [ "$BUILDER_TYPE" = "native" ]; then
  AR=gcc-ar
  NM=gcc-nm
  TARGET_FLAGS="--build=arm-linux-gnueabi --host=arm-linux-gnueabi --target=arm-linux-gnueabi"
  BOOTCYCLE=yes
else
  echo "Error! Please specify valid builder type." >&2
  echo "Acceptable values:" >&2
  echo "BUILDER_TYPE=native" >&2
  echo "BUILDER_TYPE=cross" >&2
  exit 1
fi

if [ "$BOOTCYCLE" = yes ]; then
  IMAGEDIR="$IMAGEDIR/../bootcycle-build/images"
fi
