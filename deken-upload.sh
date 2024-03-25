#!/bin/bash -e

# to be called from the pub/ directory (here)
usage="usage: toolchain-upload.sh OS(linux/windows/macos) ARCH(i386/amd64/arm32/arm64) [test]"

VERSION="0.1.0" # `git describe --abbrev=0`

oses="linux macos windows"
arches="i386 amd64 arm32 arm64"

os=$1
arch=$2

declare -A deken_os
deken_os[linux]=Linux
deken_os[macos]=Darwin
deken_os[windows]=Windows

declare -A deken_arch
deken_arch[i386]=i386
deken_arch[amd64]=amd64
deken_arch[arm32]=arm
deken_arch[arm64]=arm64

in_array() {
    local key=$1
    shift
    local a="$@"
    if [[ ${a[*]} =~ (^|[[:space:]])$key($|[[:space:]]) ]] ; then
        return 0
    else
        return 1
    fi
}

if ! $(in_array $os $oses) ; then
    echo error: unknown os $os
    echo $usage
    exit
    fi

if ! $(in_array $arch $arches) ; then
    echo error: unknown arch $arch
    echo $usage
    exit
    fi

# arm gcc: https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

extract="tar -xzf"
binpath=$os-$arch
case $binpath in
    linux-amd64)
        cmake_url=https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-linux-x86_64.tar.gz
        extract_make="tar -xzf"
        gcc_url=https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
        extract_gcc="tar -xJf"
        gccver=13.2.1
        ;;
    #linux-arm64)
    #    ;;
    windows-amd64)
        #cmake_url=https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-windows-x86_64.zip
        #gcc_url=https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-mingw-w64-i686-arm-none-eabi.zip
        #extract="unzip"
        pico_setup_url=https://github.com/raspberrypi/pico-setup-windows/releases/download/v1.5.1/pico-setup-windows-x64-standalone.exe
        gccver=10.3.1
        ;;
    macos-amd64)
        cmake_url=https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-macos-universal.tar.gz
        gcc_url=https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.10/gcc-arm-none-eabi-10.3-2021.10-mac.tar.bz2
        gccver=10.3.1
        extract_gcc="tar -xjf"
        ;;
    macos-arm64)
        cmake_url=https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-macos-universal.tar.gz
        gcc_url=https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-darwin-arm64-arm-none-eabi.tar.xz
        gccver=13.2.1
        extract_gcc="tar -xJf"
        ;;
    *) echo "os-arch not supported (yet)"
    return ;;
    esac

mkdir -p build/Fraise-toolchain/bin
cd build
build_path=$(pwd)

# ----------------- copy bins and pic-sdk
cp ../bin/$binpath/* Fraise-toolchain/bin
cp -r ../pic-sdk Fraise-toolchain/

if [ $os == windows ] ; then
    pico_setup_file=$(basename $pico_setup_url)
    pico_windows_path=Fraise-toolchain/pico-windows
    # pacman -S p7zip
    if ! [ -e $pico_windows_path ] ; then
        if ! [ -e $pico_setup_file ] ; then
            wget $pico_setup_url
        fi
        7z x -o$pico_windows_path $pico_setup_file
    fi
    cmake_path=$pico_windows_path/cmake
    gcc_path=$pico_windows_path/gcc-arm-none-eabi
    pico_sdk_path=$pico_windows_path/pico-sdk
    rm -rf $pico_windows_path/{pico-examples.zip,git,openocd}
else
    # ----------------- clone pico-sdk
    pico_sdk_path=Fraise-toolchain/pico-sdk
    if ! [ -e $pico_sdk_path ] ; then
        git clone https://github.com/raspberrypi/pico-sdk.git $pico_sdk_path
        cd $pico_sdk_path
        git submodule init
        git submodule update
        cd -
        fi
    # ----------------- get cmake
    cmake_path=Fraise-toolchain/cmake
    cmake_file=$(basename $cmake_url)
    cmake_dir="${cmake_file%.*}" # remove ".gz"
    cmake_dir="${cmake_dir%.*}"

    if ! [ -e $cmake_path ] ; then
        if ! [ -e $cmake_file ] ; then
            wget $cmake_url
        fi
        $extract $cmake_file
        if [ $os == macos ] ; then
            rm -rf $cmake_dir/CMake.app/Contents/{MacOS,Frameworks,PlugIns,_CodeSignature,Resources,CodeResources,Info.plist}
            mv $cmake_dir/CMake.app/Contents $cmake_path
            rm -rf $cmake_dir
        else
            mv $cmake_dir $cmake_path
        fi
    fi
    # ----------------- get gcc
    gcc_path=Fraise-toolchain/gcc
    gcc_file=$(basename $gcc_url)
    gcc_dir="${gcc_file%.*}" # remove ".xz"
    gcc_dir="${gcc_dir%.*}" # remove ".tar"

    if ! [ -e $gcc_path ] ; then
        if ! [ -e $gcc_file ] ; then
            wget $gcc_url
        fi
        mkdir -p $gcc_path
        $extract_gcc $gcc_file -C $gcc_path --strip-components=1
    fi
fi

# remove unused stuff in sdk-pico

cd $pico_sdk_path
rm -rf .git/ docs/* test/ lib/mbedtls/tests
touch docs/CMakeLists.txt
cd lib/tinyusb/hw
    mv mcu/raspberry_pi .
    mv bsp/rp2040 bsp/family_support.cmake .
    rm -rf mcu/*
    rm -rf bsp/*
    mv raspberry_pi mcu/
    mv rp2040 family_support.cmake bsp/
    cd -
cd lib/tinyusb/src/
    mv portable/raspberrypi .
    rm -rf portable/*
    mv raspberrypi portable/
    cd -
rm -rf lib/tinyusb/{lib,test,examples}

rm -rf lib/btstack/{port,test,example,doc,3rd-party/lwip}
cd $build_path

# remove unused stuff in cmake

rm -rf $cmake_path/bin/{cmake-gui,ccmake,ctest,cpack}*
rm -rf $cmake_path/{doc,man}


# remove unused stuff in gcc

cd $gcc_path
cd arm-none-eabi/lib
    mv thumb/{nofp,v6-m} .
    rm -rf thumb/*
    mv nofp v6-m thumb/
    cd -
cd lib/gcc/arm-none-eabi/${gccver}/
    mv thumb/{nofp,v6-m} .
    rm -rf thumb/*
    mv nofp v6-m thumb/
    cd -
cd arm-none-eabi/include/c++/${gccver}/arm-none-eabi
    mv thumb/{nofp,v6-m} .
    rm -rf thumb/*
    mv nofp v6-m thumb
    cd -
rm -rf share/{doc,info,man,gdb,gcc-arm-none-eabi}
rm -rf bin/{arm-none-eabi-gdb,arm-none-eabi-lto-dump,arm-none-eabi-gfortran}*

cd $build_path

# ----------------- package to deken
echo $os $arch deken_os[$os] $deken_arch[$arch]
DEKEN_ARCH=${deken_os[$os]}-${deken_arch[$arch]}-32
echo deken arch: $DEKEN_ARCH
deken package --version $VERSION Fraise-toolchain

mv "Fraise-toolchain[v$VERSION](Sources).dek"        "Fraise-toolchain[v$VERSION]($DEKEN_ARCH).dek"
mv "Fraise-toolchain[v$VERSION](Sources).dek.sha256" "Fraise-toolchain[v$VERSION]($DEKEN_ARCH).dek.sha256"
if [ -e "Fraise-toolchain[v$VERSION](Sources).dek.asc" ]; then
mv "Fraise-toolchain[v$VERSION](Sources).dek.asc"    "Fraise-toolchain[v$VERSION]($DEKEN_ARCH).dek.asc"
fi

if [ x$3 != xtest ] ; then
    deken upload --no-source-error "Fraise-toolchain[v$VERSION]($DEKEN_ARCH).dek"
fi

echo OK


