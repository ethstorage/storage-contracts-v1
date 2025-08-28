#!/usr/bin/env bash


extract_current_source_version() {
  local file="${1:-contracts/EthStorageContract.sol}"
  if [ ! -f "$file" ]; then
    echo "Error: $file not found" >&2
    return 2
  fi
  local v
  v=$(sed -nE 's/.*string[[:space:]]+public[[:space:]]+constant[[:space:]]+version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$file" | tr -d ' ' | tail -1)
  if [ -z "$v" ]; then
    echo "Error: version constant not found in $file" >&2
    return 2
  fi
  echo "$v"
}

# Compare semantic versions: returns 0 if equal, 1 if v1>v2, 2 if v1<v2
semantic_compare() {
  if [[ $1 == $2 ]]; then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
  for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do ver2[i]=0; done
  for ((i=0; i<${#ver1[@]}; i++)); do
    [[ -z ${ver2[i]} ]] && ver2[i]=0
    if ((10#${ver1[i]} > 10#${ver2[i]})); then return 1; fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then return 2; fi
  done
  return 0
}

compare_version() {
  local reference_dir="$1"
  local current_version="$2" 
  local deployed_version="" deployed_version_full=""

  if [[ "$reference_dir" =~ build-info-v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    deployed_version="${BASH_REMATCH[1]}"
  else
    echo "Error: Could not parse version from reference directory name: $reference_dir"
    return 2
  fi

  if [[ "$reference_dir" =~ build-info-v([0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+) ]]; then
    deployed_version_full="${BASH_REMATCH[1]}"
  else
    echo "Error: Could not parse version from reference directory name: $reference_dir"
    return 2
  fi

  local GIT_COMMIT; GIT_COMMIT=$(git rev-parse --short HEAD)
  echo ""
  echo "Upgrading contract from v$deployed_version_full to v$current_version-$GIT_COMMIT"

  semantic_compare "$current_version" "$deployed_version"
  case $? in
    0) echo "⚠️  Semantic versions are identical"; return 0 ;;
    1) return 1 ;;  # current > deployed
    2) echo "⚠️  WARNING: Current version is LOWER than deployed version!"; return 0 ;;
  esac
}

setup_environment() {

    export SOURCE_VERSION=$(extract_current_source_version) || { echo "Error: failed to extract version from source"; exit 2; }
    echo "Current semantic version from source code: v$SOURCE_VERSION"
    
    # Go to project root directory
    cd "$(dirname "$0")/.."

    if [ ! -f .env ]; then
        echo "Error: .env file not found."
        exit 1
    fi
    source .env

    VERIFY_ARGS=()

    # Network-specific settings
    if [[ "$CONTRACT_NAME" == *L2 ]]; then
        export STORAGE_COST="$STORAGE_COST_L2"
        export MINIMUM_DIFF="$MINIMUM_DIFF_L2"
        export PREPAID_AMOUNT="$PREPAID_AMOUNT_L2"
        RPC_URL="$RPC_URL_L2"
        VERIFY_ARGS+=(--verify --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL")
    else
        export STORAGE_COST="$STORAGE_COST_L1"
        export MINIMUM_DIFF="$MINIMUM_DIFF_L1"
        export PREPAID_AMOUNT="$PREPAID_AMOUNT_L1"
        RPC_URL="$RPC_URL_L1"
        VERIFY_ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
    fi

    export CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")

    # Skip verification for local chain
    if [ "${CHAIN_ID}" -eq 31337 ]; then
        VERIFY_ARGS=()
    fi
    export VERIFY_ARGS
    export RPC_URL

    if [[ "$PRIVATE_KEY" != 0x* ]]; then
        export PRIVATE_KEY="0x$PRIVATE_KEY"
    fi

    export TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    echo "RPC URL: $RPC_URL"
    echo "Chain ID: $CHAIN_ID"
    LOG_PATH="deployments/logs"
    mkdir -p ${LOG_PATH}
    export LOG_FILE="${LOG_PATH}/${TIMESTAMP}_${CONTRACT_NAME}_${CHAIN_ID}.log"
}

setup_upgrade_environment() {

    if [ ! -f "$DEPLOYMENT_FILE" ]; then
        echo "Error: Deployment file '$DEPLOYMENT_FILE' not found."
        exit 1
    fi

    source "$DEPLOYMENT_FILE"

    echo "Upgrading based on: $DEPLOYMENT_FILE"
    echo "Proxy address: $PROXY"

    if [ -z "$PROXY" ]; then
        echo "Error: PROXY address not found in deployment file"
        exit 1
    fi

    if [ -z "$START_TIME" ]; then
    echo "Error: START_TIME not found in deployment file"
    exit 1
    fi

    export CONTRACT_NAME
    export PROXY
    export START_TIME

    # Only export reference variables if they exist and are not empty
    if [ -n "$REFERENCE_BUILD_INFO_DIR" ]; then
        export REFERENCE_BUILD_INFO_DIR
        echo "Using reference build info dir: $REFERENCE_BUILD_INFO_DIR"
    else
        echo "Error: REFERENCE_BUILD_INFO_DIR not set or empty"
        exit 1
    fi

    if [ ! -d "$REFERENCE_BUILD_INFO_DIR" ]; then
        echo "Error: Reference build info directory '$REFERENCE_BUILD_INFO_DIR' does not exist."
        exit 1
    fi

    if [ -n "$REFERENCE_CONTRACT" ]; then
        export REFERENCE_CONTRACT
        echo "Using reference contract: $REFERENCE_CONTRACT"
    else
        echo "Error: REFERENCE_CONTRACT not set or empty"
        exit 1
    fi
}

check_upgrade_versions() {
    
    CUR_VERSION=$(cast call "$PROXY" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')
    echo "Current on-chain version: $CUR_VERSION"

    # extract version from reference build-info dir
    if [[ "$REFERENCE_BUILD_INFO_DIR" =~ build-info-v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        REF_VERSION="${BASH_REMATCH[1]}"
    else
        echo "Error: Could not parse version from reference directory name: $REFERENCE_BUILD_INFO_DIR"
        exit 1
    fi
    echo "Old version from reference build info: v$REF_VERSION"
    semantic_compare "$CUR_VERSION" "$REF_VERSION"
    if [ $? -ne 0 ]; then
        echo "Error: Onchain version ($CUR_VERSION) does not match reference version ($REF_VERSION)"
        exit 1
    fi

    if compare_version "$REFERENCE_BUILD_INFO_DIR" "$SOURCE_VERSION"; then
        echo ""
        read -p "Do you want to continue with the upgrade anyway? (y/N): " -n 1 -r
        echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Upgrade cancelled by user."
        exit 0
    fi
        echo "Continuing with upgrade..."
    fi
}

backup_build_info() {
    local version_tag="$1"
    if [ -z "$version_tag" ]; then
        echo "Error: backup_build_info requires a version tag" >&2
        return 2
    fi
    local dir="old-builds/build-info-${version_tag}"
    if [ -d "$dir" ]; then
        rm -rf "$dir"
    fi
    mkdir -p "old-builds"
    if [ ! -d "out/build-info" ]; then
        echo "Error: out/build-info not found. Did you run forge build/script?" >&2
        return 2
    fi
    cp -r out/build-info "$dir"
    echo "$dir"
}