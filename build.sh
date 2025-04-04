#!/bin/bash
#
# Compile script for Elaina kernel
# Copyright (C) 2020-2021 RavensVenix.

SECONDS=0 # builtin bash timer
ZIPNAME="Elaina-KernelSU-Next-surya-$(date '+%Y%m%d-%H%M').zip"
TC_DIR="$(pwd)/tc/clang-20"
AK3_DIR="$(pwd)/android/AnyKernel3"
DEFCONFIG="surya_defconfig"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

export PATH="$TC_DIR/bin:$PATH"

sync_repo() {
    local dir=$1
    local repo_url=$2
    local branch=$3
	local update=$4

    if [ -d "$dir" ]; then
        if $update; then
			# Fetch the latest changes
            git -C "$dir" fetch origin --quiet

            # Compare local and remote commits
            LOCAL_COMMIT=$(git -C "$dir" rev-parse HEAD)
            REMOTE_COMMIT=$(git -C "$dir" rev-parse "origin/$branch")

            # If there are changes, reset and log the update
            if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
                git -C "$dir" reset --quiet --hard "origin/$branch"
                LATEST_COMMIT=$(git -C "$dir" log -1 --oneline)
                echo -e "Updated $repo_url to: $LATEST_COMMIT\n" | tee -a "$dir/updates.txt"
            else
                echo "No changes found for $repo_url. Skipping update."
            fi
        fi
    else
        # Clone the repository if it doesn't exist
        echo "Cloning $repo_url to $dir..."
        if ! git clone --quiet --depth=1 -b "$branch" "$repo_url" "$dir"; then
            echo "Cloning failed! Aborting..."
            exit 1
        fi
    fi
}

if [[ $1 = "-u" || $1 = "--update" ]]; then
    sync_repo $AK3_DIR "https://github.com/RavensVenix/AnyKernel3.git" "master" true
    sync_repo $TC_DIR "https://bitbucket.org/rdxzv/clang-standalone.git" "20" true
	exit
else
    sync_repo $AK3_DIR "https://github.com/RavensVenix/AnyKernel3.git" "master" false
    sync_repo $TC_DIR "https://bitbucket.org/rdxzv/clang-standalone.git" "20" false
fi

if [ ! -d "$AK3_DIR" ] || [ ! -d "$TC_DIR" ]; then
    echo "Error: Required directories are missing. Aborting the build process."
    exit 1
fi

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-rf" || $1 = "--regen-full" ]]; then
	make $DEFCONFIG
	cp out/.config arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated full defconfig at $DEFCONFIG"
	exit
fi

CLEAN_BUILD=false
ENABLE_KSU=false
ENABLE_RWMEM=false
ENABLE_YAMA=false
ENABLE_SUSFS=false

for arg in "$@"; do
	case $arg in
		-c|--clean)
			CLEAN_BUILD=true
			;;
		--rwmem)
			ENABLE_RWMEM=true
			;;
		--yama)
			ENABLE_YAMA=true
			;;
		--susfs)
			ENABLE_SUSFS=true
			;;
		--ksu-next)
			ENABLE_KSU=true
			;;
		*)
			echo "Unknown argument: $arg"
			exit 1
			;;
	esac
done

if $CLEAN_BUILD; then
	echo "Cleaning output directory..."
	rm -rf out
fi

if $ENABLE_KSU; then
    echo "Building with KSU-Next support..."
	git clone https://github.com/KernelSU-Next/KernelSU-Next.git
	cd ./KernelSU-Next/kernel
	bash setup.sh
fi

if $ENABLE_KSU && $ENABLE_SUSFS; then
    echo "Building with KSU-Next and SUSFS support..."
	git clone https://github.com/KernelSU-Next/KernelSU-Next.git
	git clone https://gitlab.com/simonpunk/susfs4ksu/-/tree/kernel-4.14.git
	cp ./susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch ./KernelSU-Next
	cd ./KernelSU-Next
	patch -p1 < 10_enable_susfs_for_ksu.patch
	cd kernel
	bash setup.sh
fi

if $ENABLE_RWMEM; then
	echo "Building with rwMem support..."
	cd drivers/
	mkdir rwmem
	cd rwmem
	wget https://github.com/Yervant7/rwMem/releases/download/v0.5.5/rwmem.zip
	unzip rwmem.zip
	rm rwmem.zip
    chmod +x setup.sh
    ./setup.sh
	cd ../../
fi

if $ENABLE_YAMA; then
	echo "Building with Yama support..."
	git submodule add --force https://github.com/RavensVenix/Yama.git
	bash Yama/kernel/setup.sh Y Yama
fi

echo -e "\nStarting compilation...\n"
make $DEFCONFIG
make -j$(nproc --all) LLVM=1 Image.gz dtb.img dtbo.img 2> >(tee log.txt >&2) || exit $?

kernel="out/arch/arm64/boot/Image.gz"
dtb="out/arch/arm64/boot/dtb.img"
dtbo="out/arch/arm64/boot/dtbo.img"

if [ -f "$kernel" ] && [ -f "$dtb" ] && [ -f "$dtbo" ]; then
	echo -e "\nKernel compiled successfully! Zipping up...\n"
	cp -r $AK3_DIR AnyKernel3
	cp $kernel $dtb $dtbo AnyKernel3
	cd AnyKernel3
	git checkout master &> /dev/null
	zip -r9 "../$ZIPNAME" * -x .git modules\* patch\* ramdisk\* README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $ZIPNAME"
else
	echo -e "\nCompilation failed!"
	exit 1
fi