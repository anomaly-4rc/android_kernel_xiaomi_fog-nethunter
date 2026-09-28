#!/bin/bash
# script BY: anomaly_arc
DEFCONFIG="vendor/fog-perf_defconfig"

export KBUILD_BUILD_USER="anomaly-arc"
export KBUILD_BUILD_HOST="VoidLinux"
export ARCH=arm64
export SUBARCH=arm64

ZIP_NAME="Quetzalcōātl-$(date +%Y%m%d-%H%M).zip"
AK3_DIR="$(pwd)/../anykernel"

export USE_CCACHE=1
export CCACHE_DIR="$HOME/.cache/ccache"
export CCACHE_NOCOMPRESS=true
export CCACHE_MAXSIZE="30G"
export CCACHE_SLOPPINESS="include_file_mtime,include_file_ctime,time_macros"

if [ -x "$(command -v ccache)" ]; then
    export CCACHE_EXEC=$(which ccache)
    ccache -M $CCACHE_MAXSIZE >/dev/null 2>&1
else
    echo "Warning: ccache tidak ditemukan, build tanpa ccache..."
    export USE_CCACHE=0
fi

export KCFLAGS="-Wno-error -Wno-unused-variable -Wno-unused-function -Wno-pointer-sign -Wno-address-of-packed-member"

if [[ $1 = "-c" || $1 = "--clean" ]]; then
    echo "Cleaning up out folder & resetting ccache stats..."
    rm -rf out
    if [ $USE_CCACHE -eq 1 ]; then ccache -z; fi
fi

mkdir -p out
echo -e "\nGenerating defconfig: $DEFCONFIG"
make O=out ARCH=arm64 $DEFCONFIG

CORES=$(nproc --all)
echo -e "\nStarting compilation on $CORES Cores (-j$CORES) via Clang 21 (Void Host) + Ccache..."

if [ $USE_CCACHE -eq 1 ]; then
    COMPILER_CC="ccache clang"
else
    COMPILER_CC="clang"
fi

make -j$CORES O=out \
     ARCH=arm64 \
     SUBARCH=arm64 \
     LLVM=1 \
     LLVM_IAS=1 \
     LD=ld.lld \
     AR=llvm-ar \
     NM=llvm-nm \
     OBJCOPY=llvm-objcopy \
     OBJDUMP=llvm-objdump \
     STRIP=llvm-strip \
     CC="$COMPILER_CC" \
     HOSTCC="gcc" \
     HOSTCXX="g++" \
     HOSTLD="ld" \
     CLANG_TRIPLE=aarch64-linux-gnu- \
     CROSS_COMPILE=aarch64-linux-gnu- \
     CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
     Image.gz dtbs

kernel="out/arch/arm64/boot/Image.gz"
dtb_dir="out/arch/arm64/boot/dts/vendor/qcom"
output_final="out/Image.gz-dtb"
dtb="out"

if [ -f "$kernel" ]; then
    echo -e "\n====================================="
    echo -e "COMPILE SUCCESSFUL"
    echo -e "-------------------------------------"
    
    if [ -d "$dtb_dir" ] && ls "$dtb_dir"/*.dtb >/dev/null 2>&1; then
        cat "$dtb_dir"/*.dtb > "$dtb/dtb_combined"
        cat "$kernel" "$dtb/dtb_combined" > "$output_final"
        echo -e "EXTRACT & MERGE PROCESS SUCCESSFUL!"
        echo -e "Flash Ready Final Result: $output_final"
    else
        echo -e "Warning: .dtb file not found in $dtb_dir"
        echo -e "Failed to create Image.gz-dtb, please check your dts configuration."
    fi
    
    # ====================================================
    # AUTO ZIP ANYKERNEL3 SECTION
    # ====================================================
    if [ -d "$AK3_DIR" ]; then
        echo -e "\n-------------------------------------"
        echo -e "Packing AnyKernel3 Zip..."
        rm -f "$AK3_DIR"/Image* "$AK3_DIR"/dtb* "$AK3_DIR"/*.zip

        cp "$output_final" "$AK3_DIR/Image.gz-dtb"
        
        cd "$AK3_DIR" || exit 1
        zip -r9 "$ZIP_NAME" * -x .git README.md *placeholder
        cd - >/dev/null || exit 1
        
        mv "$AK3_DIR/$ZIP_NAME" out/
        rm -f "$AK3_DIR/Image.gz-dtb"
        
        echo -e "ZIP Created Successfully: out/$ZIP_NAME"
    else
        echo -e "\nWarning: AnyKernel3 directory ($AK3_DIR) not found! Skipping zip creation."
    fi
    # ====================================================
    
    echo -e "-------------------------------------"
    if [ $USE_CCACHE -eq 1 ]; then
        echo -e "Ccache Status After Build:"
        ccache -s
    fi
    echo -e "====================================="
else
    echo -e "\nCompilation Failed!"
    exit 1
fi
