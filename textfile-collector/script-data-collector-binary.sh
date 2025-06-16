#!/bin/bash

# Add Docker environment variables manually
source /home/monad/.env 
source /home/monad/.bashrc 
source /home/monad/.profile

# Get validator DNS
VALIDATOR_DNS=$(grep 'VALIDATOR_DNS' /home/monad/monad/monad-monitoring/.env | cut -d '=' -f2) || { echo "VALIDATOR_DNS not found in .env"; exit 1; }

TARGET_DRIVE=$(grep 'TARGET_DRIVE' /home/monad/.env | cut -d '=' -f2) || { echo "TARGET_DRIVE not found in .env"; exit 1; }

# Extract the used and total capacity from local monad_mpt binary
used_with_unit=$(/usr/local/bin/monad-mpt --storage /dev/$TARGET_DRIVE | grep -A 1 'Capacity' | tail -n 1 | awk '{print $3, $4}' | tr -d '\r') || { echo "Failed to get used capacity"; exit 1; }
capacity_with_unit=$(/usr/local/bin/monad-mpt --storage /dev/$TARGET_DRIVE | grep -A 1 'Capacity' | tail -n 1 | awk '{print $1, $2}' | tr -d '\r') || { echo "Failed to get total capacity"; exit 1; }

# Convert total capacity to bytes
if [[ "${capacity_with_unit,,}" == *"tb"* ]]; then
    capacity=$(echo "$capacity_with_unit" | sed 's/[Tt][Bb]//')
    capacity_bytes=$(echo "$capacity * 1024 * 1024 * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${capacity_with_unit,,}" == *"gb"* ]]; then
    capacity=$(echo "$capacity_with_unit" | sed 's/[Gg][Bb]//')
    capacity_bytes=$(echo "$capacity * 1024 * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${capacity_with_unit,,}" == *"mb"* ]]; then
    capacity=$(echo "$capacity_with_unit" | sed 's/[Mm][Bb]//')
    capacity_bytes=$(echo "$capacity * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${capacity_with_unit,,}" == *"kb"* ]]; then
    capacity=$(echo "$capacity_with_unit" | sed 's/[Kk][Bb]//')
    capacity_bytes=$(echo "$capacity * 1024" | bc | awk '{printf "%.0f", $0}')
else
    echo "Unexpected capacity unit. Exiting."
    exit 1
fi

# Convert used capacity to bytes
if [[ "${used_with_unit,,}" == *"tb"* ]]; then
    used=$(echo "$used_with_unit" | sed 's/[Tt][Bb]//')
    used_bytes=$(echo "$used * 1024 * 1024 * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${used_with_unit,,}" == *"gb"* ]]; then
    used=$(echo "$used_with_unit" | sed 's/[Gg][Bb]//')
    used_bytes=$(echo "$used * 1024 * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${used_with_unit,,}" == *"mb"* ]]; then
    used=$(echo "$used_with_unit" | sed 's/[Mm][Bb]//')
    used_bytes=$(echo "$used * 1024 * 1024" | bc | awk '{printf "%.0f", $0}')
elif [[ "${used_with_unit,,}" == *"kb"* ]]; then
    used=$(echo "$used_with_unit" | sed 's/[Kk][Bb]//')
    used_bytes=$(echo "$used * 1024" | bc | awk '{printf "%.0f", $0}')
else
    echo "Unexpected used unit. Exiting."
    exit 1
fi

# Calculate available bytes
avail_bytes=$(echo "$capacity_bytes - $used_bytes" | bc | awk '{printf "%.0f", $0}')

# Get current epoch from syslog
current_epoch=$(tail -5000 /var/log/syslog | grep -o 'epoch: [0-9]*' | tail -n 1 | awk '{print $2}') || { echo "Failed to get current epoch"; current_epoch=0; }

# Get current round from syslog
current_round=$(tail -5000 /var/log/syslog | grep -o 'round: [0-9]*' | tail -n 1 | awk '{print $2}') || { echo "Failed to get current round"; current_round=0; }

# Get forkpoint file count
forkpoint_dir_count=$(find /home/monad/monad-bft/config/forkpoint -type f | wc -l) || { echo "Failed to get forkpoint file count"; forkpoint_dir_count=0; }

# Get ledger file count
ledger_dir_count=$(find /home/monad/monad-bft/ledger -type f | wc -l) || { echo "Failed to get ledger file count"; ledger_dir_count=0; }

# Get wal file count
wal_dir_count=$(find /home/monad/monad-bft/ -type f -name "wal_*" | wc -l) || { echo "Failed to get wal file count"; wal_dir_count=0; }

# Get the directory where the script is stored
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set the output file path relative to the script's location
output_file="$script_dir/data/monad-metrics-data.prom"

# Extract block proposals and skipped blocks from syslog
mapfile -t block_logs < <(tail -500000 /var/log/syslog | grep -i "${VALIDATOR_DNS}\|${VALIDATOR_DNS}:8000" | grep -E '"message":"(proposed_block|skipped_block)"')

# Process each block log
declare -a block_proposals
for log in "${block_logs[@]}"; do
    # Extract timestamp and convert to readable format
    timestamp=$(echo "$log" | sed -n 's/.*"timestamp":"\(202[0-9]-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\.[0-9]\+Z\)".*/\1/p')
    readable_timestamp=$(date -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "1970-01-01 00:00:00")

    # Extract round
    round=$(echo "$log" | grep -o '"round":"[0-9]*"' | cut -d':' -f2 | tr -d '"')

    # Extract seq_num and num_tx
    seq_num=$(echo "$log" | grep -o '"seq_num":"[0-9]*"' | cut -d':' -f2 | tr -d '"')
    num_tx=$(echo "$log" | grep -o '"num_tx":"[0-9]*"' | cut -d':' -f2 | tr -d '"')

    # Determine block type and value
    if echo "$log" | grep -q '"message":"proposed_block"'; then
        block_type="proposed"
        value=1
    elif echo "$log" | grep -q '"message":"skipped_block"'; then
        block_type="skipped"
        value=0
    fi

    # Only add if we have valid data
    if [[ -n "$round" && "$round" != "0" && -n "$block_type" ]]; then
        # Use default values if seq_num or num_tx are not found
        seq_num=${seq_num:-"0"}
        num_tx=${num_tx:-"0"}
        block_proposals+=("mc_block_proposal{validator=\"${VALIDATOR_DNS}\", round=\"${round}\", type=\"${block_type}\", seq_num=\"${seq_num}\", num_tx=\"${num_tx}\", time_stamp=\"${readable_timestamp}\"} $value")
    fi
done

# Write all metrics to the output file
{
    printf "# HELP mc_triedb_total_bytes Total capacity of /dev/$TARGET_DRIVE\n"
    printf "# TYPE mc_triedb_total_bytes gauge\n"
    printf "mc_triedb_total_bytes %s\n" "$capacity_bytes"

    printf "# HELP mc_triedb_used_bytes Used capacity of /dev/$TARGET_DRIVE\n"
    printf "# TYPE mc_triedb_used_bytes gauge\n"
    printf "mc_triedb_used_bytes %s\n" "$used_bytes"

    printf "# HELP mc_triedb_avail_bytes Available capacity of /dev/$TARGET_DRIVE\n"
    printf "# TYPE mc_triedb_avail_bytes gauge\n"
    printf "mc_triedb_avail_bytes %s\n" "$avail_bytes"

    printf "# HELP mc_current_epoch provides Monad epoch from logs\n"
    printf "# TYPE mc_current_epoch gauge\n"
    printf "mc_current_epoch %s\n" "$current_epoch"

    printf "# HELP mc_current_round provides Monad round from logs\n"
    printf "# TYPE mc_current_round gauge\n"
    printf "mc_current_round %s\n" "$current_round"

    printf "# HELP mc_forkpoint_dir_count provides file count of Monad forkpoint directory\n"
    printf "# TYPE mc_forkpoint_dir_count gauge\n"
    printf "mc_forkpoint_dir_count %s\n" "$forkpoint_dir_count"

    printf "# HELP mc_ledger_dir_count provides file count of Monad ledger directory\n"
    printf "# TYPE mc_ledger_dir_count gauge\n"
    printf "mc_ledger_dir_count %s\n" "$ledger_dir_count"

    printf "# HELP mc_wal_dir_count provides file count of Monad wal files\n"
    printf "# TYPE mc_wal_dir_count gauge\n"
    printf "mc_wal_dir_count %s\n" "$wal_dir_count"

    # Write block proposals
    if [ ${#block_proposals[@]} -gt 0 ]; then
        printf "# HELP mc_block_proposal Indicates a block was proposed (1) or skipped (0) by this validator, with additional sequence and transaction details\n"
        printf "# TYPE mc_block_proposal gauge\n"
        for proposal in "${block_proposals[@]}"; do
            printf "%s\n" "$proposal"
        done
    fi
} > "$output_file" 2>/dev/null || { echo "Cannot write to monad-metrics-data.prom"; exit 1; }
