# Install Vulkan drivers matching detected GPU hardware
# (NVIDIA Vulkan is handled by nvidia.sh via nvidia-utils)
# The GMA 950 (i945) has no Vulkan driver at all: ANV starts at Gen7.

if ! lspci -n | grep -q "8086:27a2"; then
  declare -A VULKAN_DRIVERS=(
    [Intel]=vulkan-intel
    [AMD]=vulkan-radeon
    [Apple]=vulkan-asahi
  )

  PACKAGES=()

  for vendor in "${!VULKAN_DRIVERS[@]}"; do
    if lspci | grep -iE "(VGA|Display).*$vendor" > /dev/null; then
      PACKAGES+=("${VULKAN_DRIVERS[$vendor]}")
    fi
  done

  if (( ${#PACKAGES[@]} > 0 )); then
    omarchy-pkg-add "${PACKAGES[@]}"
  fi
fi
