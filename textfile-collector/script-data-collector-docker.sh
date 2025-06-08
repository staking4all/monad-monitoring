#!/bin/bash

# Add Docker environment variables manually
source /home/monad/.env
source /home/monad/.bashrc
source /home/monad/.profile

#not needed once rootless docker not being used
#export XDG_RUNTIME_DIR=/run/user/$(id -u)
#export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock

TARGET_DRIVE=$(grep 'TARGET_DRIVE' /home/monad/.env | cut -d '=' -f2)

# Extract the used and total capacity from specific positions
used_with_unit=$(docker exec monad-execution-1 sh -c "/usr/local/bin/monad_mpt --storage /dev/$TARGET_DRIVE | grep -A 1 'Used' | tail -n 1 | awk '{print \$3, \$4}'"  | tr -d '\r')
capacity_with_unit=$(docker exec monad-execution-1 sh -c "/usr/local/bin/monad_mpt --storage /dev/$TARGET_DRIVE | grep -A 1 'Capacity' | tail -n 1 | awk '{print \$1, \$2}'" | tr -d '\r')

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

#Get current epoch
current_epoch=$(docker logs --tail 500 monad-bft-1 | grep -o 'epoch: [0-9]*' | tail -n 1 | awk '{print $2}')

#Get Current round
current_round=$(docker logs --tail 500 monad-bft-1 | grep -o 'round: [0-9]*' | tail -n 1 | awk '{print $2}')

#Get forkpoint file count
forkpoint_dir_count=$(find /home/monad/monad-bft/config/forkpoint -type f | wc -l)

#Get ledger file count
ledger_dir_count=$(find /home/monad/monad-bft/ledger -type f | wc -l)

#Get wal file count
wal_dir_count=$(find /home/monad/monad-bft/ -type f -name "wal_*" | wc -l)

# Get the directory where the script is stored
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set the output file path relative to the script's location
output_file="$script_dir/data/monad-metrics-data.prom"
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

  printf "# HELP mc_forkpoint_dir_count provides file count of Monad forkpopint directory "
  printf "# TYPE mc_forkpoint_dir_count gauge\n"
  printf "mc_forkpoint_dir_count %s\n" "$forkpoint_dir_count"

  printf "# HELP mc_ledger_dir_count provides file count of Monad ledger directory "
  printf "# TYPE mc_ledger_dir_count gauge\n"
  printf "mc_ledger_dir_count %s\n" "$ledger_dir_count"

  printf "# HELP mc_wal_dir_count provides file count of Monad wal files "
  printf "# TYPE mc_wal_dir_count gauge\n"
  printf "mc_wal_dir_count %s\n" "$wal_dir_count"

} > "$output_file"
