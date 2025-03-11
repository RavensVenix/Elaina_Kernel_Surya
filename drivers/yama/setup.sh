#!/bin/sh
# copied from KernelSU repo

set -eu

GKI_ROOT=$(pwd)

display_usage() {
    echo "Usage: $0 [--cleanup | <integration-options>]"
    echo "  --cleanup:              Cleans up previous modifications made by the script."
    echo "  <integration-options>:   Tells us how Yama should be integrated into kernel source (Y, M)."
    echo "  <driver-name>:          Optional argument, should be used after <integration-options>. if not mentioned random name will be used."
    echo "  -h, --help:             Displays this usage information."
    echo "  (no args):              Sets up or updates the Yama environment to the latest commit (integration as Y)."
}

initialize_variables() {
    if [ -d "$GKI_ROOT/common/drivers" ]; then
         DRIVER_DIR="$GKI_ROOT/common/drivers"
    elif [ -d "$GKI_ROOT/drivers" ]; then
         DRIVER_DIR="$GKI_ROOT/drivers"
    else
        DRIVER_DIR=""
    fi

    DRIVER_MAKEFILE="$DRIVER_DIR/Makefile"
    DRIVER_KCONFIG="$DRIVER_DIR/Kconfig"
}

perform_cleanup() {
    echo "[+] Cleaning up..."
    if [ -n "$DRIVER_DIR" ]; then
        [ -L "$DRIVER_DIR/yama" ] && rm "$DRIVER_DIR/yama" && echo "[-] Symlink removed."
        grep -q "yama" "$DRIVER_MAKEFILE" && sed -i '/yama/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
        grep -q "drivers/yama/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/yama\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    fi
    [ -d "$GKI_ROOT/Yama" ] && rm -rf "$GKI_ROOT/Yama" && echo "[-] Yama directory deleted."
}

randomize_driver_and_module() {
    local random_name
    if [ -n "${1:-}" ]; then
        random_name="$1"
    else
        random_name=$(tr -dc 'a-z' </dev/urandom | head -c 6)
    fi

    sed -i "s/#define DEVICE_NAME \".*\"/#define DEVICE_NAME \"$random_name\"/" "$GKI_ROOT/Yama/kernel/entry.c"
    sed -i "s|#define DEVICE_NAME \"/dev/.*\"|#define DEVICE_NAME \"/dev/$random_name\"|" "$GKI_ROOT/Yama/user/driver.hpp"

    if [ "$2" = "M" ]; then
        sed -i "s/yama.o/${random_name}_memk.o/" "$GKI_ROOT/Yama/kernel/Makefile"
        sed -i "s/yama-y/${random_name}_memk-y/" "$GKI_ROOT/Yama/kernel/Makefile"
        echo -e "\e[36mModule Name: ${random_name}_memk.ko\e[0m"
    fi

    echo -e "\e[36mDevice Name: $random_name\e[0m"
}

setup_yama() {
    if [ -z "$DRIVER_DIR" ]; then
        echo '[ERROR] "drivers/" directory not found.'
        exit 127
    fi
    
    echo "[+] Setting up Yama..."
    [ -d "$GKI_ROOT/Yama" ] || git clone https://github.com/RavensVenix/Yama && echo "[+] Repository cloned."
    cd "$GKI_ROOT/Yama"
    git stash && echo "[-] Stashed current changes."
    git checkout main && git pull && echo "[+] Repository updated."

    if [ "$1" = "M" ]; then
        sed -i 's/default y/default m/' kernel/Kconfig
    elif [ "$1" != "Y" ]; then
        echo "[ERROR] First argument not valid. should be any of these: Y, M"
        exit 128
    fi

    cd "$DRIVER_DIR"
    ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/Yama/kernel")" "yama" && echo "[+] Symlink created."

    # Add entries in Makefile and Kconfig if not already exists
    grep -q "yama" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_YAMA) += yama/\n" >> "$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
    grep -q "source \"drivers/yama/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\source \"drivers/yama/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."

    if [ "$#" -ge 2 ]; then
        randomize_driver_and_module "$2" "$1"
    else
        randomize_driver_and_module "" "$1"
    fi
    echo '[+] Done.'
}

# Process command-line arguments
if [ "$#" -eq 0 ]; then
    set -- Y
fi

case "$1" in
    -h|--help)
        display_usage
        ;;
    --cleanup)
        initialize_variables
        perform_cleanup
        ;;
    *)
        initialize_variables
        if [ "$#" -eq 0 ]; then
            setup_yama Y
        else
            setup_yama "$@"
        fi
        ;;
esac
