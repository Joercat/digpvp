#!/bin/bash

JAVA_HOME_DIR=$(find /usr/lib/jvm -maxdepth 1 -name "java-17-openjdk-*" -type d 2>/dev/null | head -1)
if [ -z "$JAVA_HOME_DIR" ]; then
    echo "ERROR: Java 17 not found!"
    exit 1
fi
JAVA="$JAVA_HOME_DIR/bin/java"

BUNGEE_DIR="/opt/server/bungee"
BACKEND_DIR="/opt/server/backend"
PLUGIN_DIR="$BACKEND_DIR/plugins"

mkdir -p "$PLUGIN_DIR"

HF_BUCKET_HANDLE="hf://buckets/smodusermc/digpvp"
SAVE_DIRS="world world_nether world_the_end players banned-ips.json banned-players.json ops.json whitelist.json plugins/WorldGuard plugins/Shopkeepers plugins/MineResetLite plugins/SafeTrade plugins/Skript plugins/WorldEdit plugins/PvPManager plugins/HolographicDisplays"SYNC_INTERVAL="${SYNC_INTERVAL:-300}"
SYNC_INTERVAL="${SYNC_INTERVAL:-300}"
IDLE_MODE=false

# =============================================
# OP ACCOUNT
# =============================================
OP_USERNAME="CreppyBitch"

CPU_CORES=$(nproc 2>/dev/null || echo 2)
NETTY_THREADS=$CPU_CORES

TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
BUNGEE_MAX_MB=1024
PAPER_MAX_MB=$(( TOTAL_MEM_MB - BUNGEE_MAX_MB - 768 ))
[ "$PAPER_MAX_MB" -gt 8192 ] && PAPER_MAX_MB=8192
[ "$PAPER_MAX_MB" -lt 1024 ] && PAPER_MAX_MB=1024
PAPER_MIN_MB=8192

echo "========================================"
echo "  Eaglercraft 1.8.8 PVP Server"
echo "  WindSpigot + HuggingFace Buckets"
echo "========================================"
echo ""
echo " CPUs: $CPU_CORES | RAM: ${TOTAL_MEM_MB}MB"
echo " Server: ${PAPER_MIN_MB}-${PAPER_MAX_MB}MB | Bungee: ${BUNGEE_MAX_MB}MB"
echo " Java: $($JAVA -version 2>&1 | head -1)"
echo " Bucket: $HF_BUCKET_HANDLE"
[ -n "$OP_USERNAME" ] && echo " OP Account: $OP_USERNAME"
echo " Plugins: WorldEdit, WorldGuard, MineResetLite, Shopkeepers, SafeTrade, Skript, PvPManager"
echo ""

# =============================================
# JVM FLAGS
# =============================================
PAPER_JVM_FLAGS=(
    -Xmx${PAPER_MAX_MB}M
    -Xms${PAPER_MIN_MB}M
    -XX:+UseG1GC
    -XX:+ParallelRefProcEnabled
    -XX:MaxGCPauseMillis=25
    -XX:+UnlockExperimentalVMOptions
    -XX:+DisableExplicitGC
    -XX:G1NewSizePercent=40
    -XX:G1MaxNewSizePercent=50
    -XX:G1HeapRegionSize=8M
    -XX:G1ReservePercent=15
    -XX:G1HeapWastePercent=10
    -XX:G1MixedGCCountTarget=8
    -XX:InitiatingHeapOccupancyPercent=60
    -XX:G1MixedGCLiveThresholdPercent=90
    -XX:G1RSetUpdatingPauseTimePercent=5
    -XX:SurvivorRatio=32
    -XX:+PerfDisableSharedMem
    -XX:MaxTenuringThreshold=1
    -XX:+OptimizeStringConcat
    -XX:+UseCompressedOops
    -XX:MaxMetaspaceSize=256M
    -XX:CompressedClassSpaceSize=128M
    -XX:ReservedCodeCacheSize=128M
    -XX:-UseCodeCacheFlushing
    -Xss256k
    -Djline.terminal=jline.UnsupportedTerminal
    -Dio.netty.allocator.maxCachedBufferCapacity=524288
    -Dio.netty.recycler.maxCapacityPerThread=0
    -Dio.netty.eventLoopThreads=${NETTY_THREADS}
    -Dio.netty.allocator.numDirectArenas=${NETTY_THREADS}
    -Dio.netty.allocator.numHeapArenas=${NETTY_THREADS}
    -Dcom.mojang.eula.agree=true
    -DIReallyKnowWhatIAmDoingISwear
    -Dusing.aikars.flags=https://mcflags.emc.gs
    -Daikars.new.flags=true
)

BUNGEE_JVM_FLAGS=(
    -Xmx${BUNGEE_MAX_MB}M
    -Xms128M
    -XX:+UseG1GC
    -XX:+ParallelRefProcEnabled
    -XX:MaxGCPauseMillis=30
    -XX:+UnlockExperimentalVMOptions
    -XX:+DisableExplicitGC
    -XX:+PerfDisableSharedMem
    -XX:+OptimizeStringConcat
    -XX:+UseCompressedOops
    -XX:MaxMetaspaceSize=128M
    -XX:ReservedCodeCacheSize=64M
    -Xss256k
    -Dio.netty.allocator.maxCachedBufferCapacity=524288
    -Dio.netty.recycler.maxCapacityPerThread=0
    -Dio.netty.eventLoopThreads=${NETTY_THREADS}
    -Dio.netty.allocator.numDirectArenas=${NETTY_THREADS}
    -Dio.netty.allocator.numHeapArenas=${NETTY_THREADS}
    -Deaglerxbungee.stfu=true
)

# =============================================================
# RCON — each command sent individually to avoid mangling
# =============================================================
RCON_PASS="chunkystart"

get_player_count() {
    local RESULT
    RESULT=$(mcrcon -H 127.0.0.1 -P 25575 -p "$RCON_PASS" "list" 2>/dev/null)
    echo "$RESULT" | grep -oE 'are [0-9]+' | grep -oE '[0-9]+' || echo "0"
}

mc_command() {
    for cmd in "$@"; do
        mcrcon -H 127.0.0.1 -P 25575 -p "$RCON_PASS" "$cmd" 2>/dev/null
    done
}

# =============================================================
# WindSpigot starter
# =============================================================
start_windspigot() {
    cd "$BACKEND_DIR"
    $JAVA "${PAPER_JVM_FLAGS[@]}" -jar server.jar nogui --noconsole >> /tmp/paper.log 2>&1 &
    BACKEND_PID=$!
}

# =============================================================
# OP Account Setup
# =============================================================
setup_op_account() {
    if [ -z "$OP_USERNAME" ]; then
        return
    fi

    echo " Setting up OP for: $OP_USERNAME"

    local OFFLINE_UUID
    OFFLINE_UUID=$(echo -n "OfflinePlayer:${OP_USERNAME}" | md5sum | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/')
    local V3_UUID
    V3_UUID=$(echo "$OFFLINE_UUID" | sed 's/.\{1\}\(.\{3\}-\)/3\1/' | sed 's/\(.\{14\}-\).\(.\{3\}-\)/\1'"$(echo "$OFFLINE_UUID" | cut -c15 | tr '0-9a-f' '89ab89ab89ab89ab')"'\2/')

    cat > "$BACKEND_DIR/ops.json" << OPEOF
[
  {
    "uuid": "${V3_UUID}",
    "name": "${OP_USERNAME}",
    "level": 4,
    "bypassesPlayerLimit": true
  }
]
OPEOF
    echo "   ops.json written (level 4, UUID: ${V3_UUID})"

    mc_command "op ${OP_USERNAME}"
    echo "   RCON op command sent"
}

# =============================================================
# IDLE MODE — safe version that does NOT kill entities
# =============================================================
enter_idle_mode() {
    [ "$IDLE_MODE" = true ] && return
    IDLE_MODE=true
    mc_command "gamerule randomTickSpeed 0"
    mc_command "gamerule doMobSpawning false"
    mc_command "kill @e[type=Zombie]"
    mc_command "kill @e[type=Skeleton]"
    mc_command "kill @e[type=Spider]"
    mc_command "kill @e[type=Creeper]"
    mc_command "kill @e[type=Enderman]"
    mc_command "kill @e[type=Witch]"
    mc_command "kill @e[type=Slime]"
    mc_command "kill @e[type=CaveSpider]"
    mc_command "kill @e[type=Silverfish]"
    mc_command "kill @e[type=Guardian]"
    mc_command "kill @e[type=Endermite]"
    mc_command "kill @e[type=Blaze]"
    mc_command "kill @e[type=Ghast]"
    mc_command "kill @e[type=MagmaCube]"
    mc_command "kill @e[type=WitherSkeleton]"
    mc_command "kill @e[type=ZombiePigman]"
    echo "[IDLE] Active — hostile mobs cleared, ticks paused"
}

exit_idle_mode() {
    [ "$IDLE_MODE" = false ] && return
    IDLE_MODE=false
    mc_command "gamerule randomTickSpeed 3"
    mc_command "gamerule doMobSpawning true"
    echo "[IDLE] Gameplay restored"
}

# =============================================================
# Port fix
# =============================================================
find_listeners_yml() {
    find "$BUNGEE_DIR/plugins" -name "listeners.yml" -type f 2>/dev/null | head -1
}

patch_eagler_port() {
    local FILE=$(find_listeners_yml)
    [ -z "$FILE" ] && return 1
    grep -q ":7860" "$FILE" && return 0
    sed -i 's/\(address:[[:space:]]*"[^:]*:\)[0-9]*/\17860/' "$FILE"
    sed -i "s/\(address:[[:space:]]*[^\"][^:]*:\)[0-9]*/\17860/" "$FILE"
    echo "  Port -> 7860"
}

start_bungee() {
    cd "$BUNGEE_DIR"
    $JAVA "${BUNGEE_JVM_FLAGS[@]}" \
        -cp "sqlite-jdbc.jar:BungeeCord.jar" \
        net.md_5.bungee.Bootstrap >> /tmp/bungee.log 2>&1 &
    BUNGEE_PID=$!
}

# =============================================================
# HuggingFace Bucket
# =============================================================
hf_authenticate() {
    if [ -n "$HF_TOKEN" ]; then
        hf auth login --token "$HF_TOKEN" --add-to-git-credential 2>/dev/null || true
        echo " Authenticated"
    else
        echo " No HF_TOKEN"
    fi
}

hf_ensure_bucket() {
    local BUCKET_ID=$(echo "$HF_BUCKET_HANDLE" | sed 's|hf://buckets/||')
    hf buckets create "$BUCKET_ID" --exist-ok 2>/dev/null
}

hf_restore_saves() {
    echo " Restoring game data..."
    hf buckets sync "${HF_BUCKET_HANDLE}/game-data" "$BACKEND_DIR" 2>&1 | tail -5
    for dir in $SAVE_DIRS; do
        [ -e "$BACKEND_DIR/$dir" ] && echo "   Found: $dir"
    done
}

hf_push_saves() {
    local STAGING="/tmp/hf-staging"
    rm -rf "$STAGING" && mkdir -p "$STAGING"
    for item in $SAVE_DIRS; do
        if [ -e "$BACKEND_DIR/$item" ]; then
            mkdir -p "$STAGING/$(dirname "$item")"
            cp -a "$BACKEND_DIR/$item" "$STAGING/$item"
        fi
    done
    hf buckets sync "$STAGING" "${HF_BUCKET_HANDLE}/game-data" --delete 2>&1 | tail -3
    [ $? -eq 0 ] && echo "[SYNC] OK $(date '+%H:%M:%S')" \
                  || echo "[SYNC] FAIL $(date '+%H:%M:%S')"
    rm -rf "$STAGING"
}

hf_sync_loop() {
    while true; do
        sleep "$SYNC_INTERVAL"
        hf_push_saves
    done
}

# =============================================================
# STEP 0: Bucket
# =============================================================
echo "[0/7] Bucket setup..."
hf_authenticate
hf_ensure_bucket
hf_restore_saves
echo ""

# =============================================================
# STEP 1: World size
# =============================================================
echo "[1/7] World analysis..."
for WORLD_DIR in world world_nether world_the_end; do
    if [ -d "$BACKEND_DIR/$WORLD_DIR" ]; then
        SIZE=$(du -sh "$BACKEND_DIR/$WORLD_DIR" 2>/dev/null | awk '{print $1}')
        REGIONS=$(find "$BACKEND_DIR/$WORLD_DIR" -name "*.mca" 2>/dev/null | wc -l)
        echo "   $WORLD_DIR: $SIZE ($REGIONS region files)"
    fi
done
echo ""

# =============================================================
# STEP 2: Core server configs + Start WindSpigot
# =============================================================
cd "$BACKEND_DIR"
echo "eula=true" > eula.txt

echo "[2/7] Writing core server configs + starting WindSpigot..."

cat > server.properties << 'EOF'
server-port=25565
server-ip=127.0.0.1
online-mode=false
spawn-protection=0
max-players=20
view-distance=6
gamemode=0
difficulty=1
level-name=world
level-type=FLAT
level-seed=8678942899319966093
generate-structures=true
motd=DigPvP Eaglercraft
pvp=true
allow-flight=false
white-list=false
spawn-npcs=true
spawn-animals=false
spawn-monsters=false
enable-command-block=false
allow-nether=false
use-native-transport=true
network-compression-threshold=-1
entity-broadcast-range-percentage=50
max-tick-time=-1
enable-rcon=true
rcon.port=25575
rcon.password=chunkystart
EOF

cat > bukkit.yml << 'EOF'
settings:
  allow-end: true
  warn-on-overload: true
  connection-throttle: -1
  shutdown-message: Server closed
  save-user-cache-on-stop-only: true
spawn-limits:
  monsters: 30
  animals: 6
  water-animals: 2
  ambient: 1
chunk-gc:
  period-in-ticks: 600
ticks-per:
  animal-spawns: 600
  monster-spawns: 4
  autosave: 12000
EOF

cat > spigot.yml << 'EOF'
config-version: 8
settings:
  bungeecord: true
  timeout-time: 60
  netty-threads: 2
  async-catcher-enabled: false
  save-user-cache-on-stop-only: true
  moved-wrongly-threshold: 0.0625
  moved-too-quickly-multiplier: 10.0
  item-dirty-ticks: 20
  player-shuffle: 0
commands:
  tab-complete: 0
  log: false
world-settings:
  default:
    verbose: false
    view-distance: 4
    mob-spawn-range: 3
    entity-activation-range:
      animals: 12
      monsters: 20
      misc: 6
      tick-inactive-villagers: false
    entity-tracking-range:
      players: 48
      animals: 32
      monsters: 32
      misc: 16
      other: 48
    ticks-per:
      hopper-transfer: 8
      hopper-check: 1
    hopper-amount: 1
    max-entity-collisions: 2
    merge-radius:
      exp: 6.0
      item: 4.0
    arrow-despawn-rate: 60
    item-despawn-rate: 3000
    nerf-spawner-mobs: true
    zombie-aggressive-towards-villager: false
    enable-zombie-pigmen-portal-spawns: false
EOF

cat > windspigot.yml << 'EOF'
settings:
  async:
    entity-tracking: true
    path-searching: true
    tnt-explosions: true
    lighting: true
  tnt:
    optimize-movement: true
    optimize-liquid-explosions: true
  fast-operators: true
  stop-decoding-itemstack-on-place: true
  modern-tick-loop:
    enabled: false
  tcp-fast-open: true
  reduced-chunk-loads: true
  lag-compensated-potions: false
  anti-xray:
    enabled: true
    engine-mode: 2
  hit-detection:
    enabled: true
    threshold: 1.0
  combat:
    knockback:
      friction: 2.0
      horizontal: 0.35
      vertical: 0.35
      vertical-limit: 0.4
      extra-horizontal: 0.425
      extra-vertical: 0.085
  chunk:
    threads: 1
    players-per-thread: 25
EOF

cat > nacho.yml << 'EOF'
settings:
  stop-notify-bungee: true
  anti-malware: true
  use-tcp-nodelay: true
  brand-name: "PVP"
EOF

setup_op_account

> /tmp/paper.log
start_windspigot
echo " WindSpigot PID: $BACKEND_PID"

for i in $(seq 1 120); do
    if grep -q "Done" /tmp/paper.log 2>/dev/null; then
        echo " WindSpigot READY (~${i}s)"
        break
    fi
    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo " WINDSPIGOT CRASHED!"
        tail -30 /tmp/paper.log
        exit 1
    fi
    [ $((i % 15)) -eq 0 ] && echo " Loading... (${i}s)"
    sleep 1
done

for i in $(seq 1 30); do
    nc -z 127.0.0.1 25575 2>/dev/null && break
    sleep 1
done

if [ -n "$OP_USERNAME" ]; then
    mc_command "op ${OP_USERNAME}"
    echo " OP granted to ${OP_USERNAME} via RCON"
fi

echo ""
echo " === PLUGINS LOADED ==="
grep -i "Enabling" /tmp/paper.log | grep -oP "Enabling \K[^\s]+" 2>/dev/null | while read p; do
    echo "   - $p"
done
echo " ======================"
echo ""

# =============================================================
# STEP 3: PVP gamerules — each command sent separately
# =============================================================
echo "[3/7] Setting PVP gamerules..."
mc_command "gamerule pvp true"
mc_command "gamerule keepInventory false"
mc_command "gamerule naturalRegeneration true"
mc_command "gamerule doFireTick true"
mc_command "gamerule mobGriefing false"
mc_command "gamerule announceAdvancements false"
mc_command "difficulty 2"
mc_command "defaultgamemode survival"
echo " PVP gamerules set"
echo ""

# =============================================================
# STEP 4: Idle mode — safe version
# =============================================================
echo "[4/7] Applying idle mode (no players)..."
enter_idle_mode
echo ""

# =============================================================
# STEP 5: Write ALL plugin configs + BungeeCord config
# =============================================================
echo "[5/7] Writing ALL plugin configs + BungeeCord config..."

# ===============================
# BUNGEE CONFIG
# ===============================
cd "$BUNGEE_DIR"

cat > config.yml << 'EOF'
server_connect_timeout: 5000
remote_ping_cache: -1
forge_support: false
player_limit: 10
permissions:
  default:
    - bungeecord.command.server
  admin:
    - bungeecord.command.alert
timeout: 30000
log_commands: false
network_compression_threshold: 256
online_mode: false
disabled_commands:
  - disabledcommandhere
servers:
  lobby:
    motd: '&aEaglercraft PVP'
    address: 127.0.0.1:25565
    restricted: false
listeners:
  - query_port: 25577
    motd: '&6Eaglercraft 1.8.8 PVP'
    tab_list: GLOBAL_PING
    query_enabled: false
    proxy_protocol: false
    forced_hosts: {}
    ping_passthrough: false
    priorities:
      - lobby
    bind_local_address: true
    host: 127.0.0.1:25577
    max_players: 10
    tab_size: 60
    force_default_server: true
ip_forward: true
remote_ping_timeout: 5000
prevent_proxy_connections: false
groups:
  default:
    - default
connection_throttle: -1
connection_throttle_limit: 0
stats: none
log_pings: false
EOF
echo "   BungeeCord config.yml written"

# ===============================
# WORLDEDIT CONFIG
# ===============================
mkdir -p "$PLUGIN_DIR/WorldEdit"
cat > "$PLUGIN_DIR/WorldEdit/config.yml" << 'WEEOF'
limits:
  allow-extra-data-values: false
  max-blocks-changed:
    default: 150000
    maximum: 200000
  max-polygonal-points:
    default: -1
    maximum: 20
  max-radius: -1
  max-super-pickaxe-size: 5
  max-brush-radius: 6
  butcher-radius:
    default: -1
    maximum: -1
  disallowed-blocks: []
use-inventory:
  enable: false
  allow-override: true
  creative-mode-overrides: false
logging:
  log-commands: false
  file: worldedit.log
super-pickaxe:
  drop-items: true
  many-drop-items: true
snapshots:
  directory:
navigation-wand:
  item: 345
  max-distance: 100
scripting:
  timeout: 3000
  dir: craftscripts
saving:
  dir: schematics
files:
  allow-symbolic-links: false
history:
  size: 15
  expiration: 10
wand-item: 271
no-double-slash: false
no-op-permissions: false
debug: false
show-help-on-first-use: true
server-side-cui: true
WEEOF
echo "   WorldEdit config written"

# ===============================
# WORLDGUARD CONFIG
# ===============================
mkdir -p "$PLUGIN_DIR/WorldGuard"
cat > "$PLUGIN_DIR/WorldGuard/config.yml" << 'WGEOF'
op-permissions: true
summary-on-start: true
auto-invincible: false
auto-invincible-group: false
auto-no-drowning-group: false
use-player-move-event: true
use-player-teleport-event: true
regions:
  enable: true
  wand: 287
  max-region-count-per-player:
    default: 7
  claim-only-inside-existing-regions: false
  max-claim-volume: 30000
  cancel-chat-without-recipients: false
  npc-flag-handling: RELATIONSHIP_API
  use-creature-spawn-event: true
  invincibility-removes-mobs: false
  high-frequency-flags: true
  protect-against-liquid-flow: false
sql:
  use: false
  dsn: jdbc:mysql://localhost/worldguard
  username: worldguard
  password: worldguard
  table-prefix: ''
  driver: ''
build-permission-nodes:
  enable: false
  deny-message: '&cSorry, you cannot build here!'
event-handling:
  block-entity-spawns-with-mob-reasons: false
  interaction-whitelist: []
security:
  deop-everyone-on-join: false
  block-in-game-op-command: false
mobs:
  block-creeper-explosions: false
  block-creeper-block-damage: true
  block-wither-explosions: false
  block-wither-block-damage: true
  block-wither-skull-explosions: false
  block-wither-skull-block-damage: true
  block-enderdragon-block-damage: true
  block-enderdragon-portal-creation: false
  block-fireball-explosions: false
  block-fireball-block-damage: true
  anti-wolf-dumbness: false
  allow-tamed-spawns: true
  disable-enderman-griefing: true
  block-painting-destroy: false
  block-item-frame-destroy: false
  block-plugin-spawning: true
  block-above-ground-slimes: false
  block-other-explosions: false
  block-zombie-door-destruction: true
  block-vehicle-entry: false
  block-creature-spawn: []
player-damage:
  disable-fall-damage: false
  disable-lava-damage: false
  disable-fire-damage: false
  disable-lightning-damage: false
  disable-drowning-damage: false
  disable-suffocation-damage: false
  disable-contact-damage: false
  disable-void-damage: false
  teleport-on-void-falling: false
  disable-explosion-damage: false
  disable-mob-damage: false
  disable-death-messages: false
ignition:
  block-tnt: false
  block-tnt-block-damage: false
  block-lighter: false
fire:
  disable-lava-fire-spread: false
  disable-all-fire-spread: false
  disable-fire-spread-blocks: []
  lava-spread-blocks: []
weather:
  prevent-lightning-strike-fire: false
  disable-lightning-strike-fire: false
  disable-thunderstorm: false
  disable-weather: false
  disable-pig-zombification: false
  disable-powered-creepers: false
  always-raining: false
  always-thundering: false
dynamics:
  disable-mushroom-spread: false
  disable-ice-melting: false
  disable-snow-melting: false
  disable-snow-formation: false
  disable-ice-formation: false
  disable-leaf-decay: false
  disable-grass-growth: false
  disable-mycelium-spread: false
  disable-vine-growth: false
  disable-crop-growth: false
  disable-soil-dehydration: false
chest-protection:
  enable: false
  disable-off-check: false
blacklist:
  use: false
  override-wildcard: true
  log:
    console: false
    database: false
    file: false
    file-path: worldguard/logs/%Y-%m-%d.log
WGEOF

mkdir -p "$PLUGIN_DIR/WorldGuard/worlds/world"
cat > "$PLUGIN_DIR/WorldGuard/worlds/world/config.yml" << 'WGWEOF'
regions:
  enable: true
  invincibility-removes-mobs: false
mobs:
  block-creeper-block-damage: true
  block-enderdragon-block-damage: true
  block-wither-block-damage: true
  disable-enderman-griefing: true
  block-zombie-door-destruction: true
player-damage:
  disable-fall-damage: false
  disable-void-damage: false
fire:
  disable-all-fire-spread: false
weather:
  disable-weather: false
WGWEOF
echo "   WorldGuard config written"

# ===============================
# MINERESETLITE CONFIG
# ===============================
mkdir -p "$PLUGIN_DIR/MineResetLite"
mkdir -p "$PLUGIN_DIR/MineResetLite/mines"
cat > "$PLUGIN_DIR/MineResetLite/config.yml" << 'MRLEOF'
broadcast-in-world-only: false
broadcast-nearby-only: false
default-mine-reset-delay: 15
MRLEOF
echo "   MineResetLite config written"

# ===============================
# SHOPKEEPERS CONFIG
# ===============================
mkdir -p "$PLUGIN_DIR/Shopkeepers"
cat > "$PLUGIN_DIR/Shopkeepers/config.yml" << 'SKEOF'
debug: false
enable-metrics: false
bypass-spawn-blocking: true
bypass-shop-interaction-blocking: false
save-instantly: true
enable-living-shops: true
disable-living-shops: false
enable-sign-shops: true
enable-citizen-shops: false
name-regex: "[A-Za-z0-9 ]{3,25}"
max-shops-per-player: 0
require-creation-permission: false
create-player-shop-with-command: false
currency-item: EMERALD
currency-item-spawn-egg-entity-type: ''
zero-currency-item: AIR
high-currency-item: EMERALD_BLOCK
high-currency-value: 9
high-currency-min-cost: 20
zero-high-currency-item: AIR
disable-other-villagers: true
block-villager-spawns: false
hire-other-villagers: false
tax-rate: 0
tax-round-up: false
protect-chests: true
prevent-item-movement: true
delete-shopkeeper-on-break-chest: false
editor-max-column: 8
enable-villager-shops: true
enable-sign-shops-only: false
enable-witch-shops: true
msg-creation-item-selected: "&aShop creation item selected."
msg-shop-create-fail: "&cCannot create shop."
msg-button-name: "&aNaming"
msg-button-type: "&aType"
msg-button-delete: "&4Delete"
msg-button-hire: "&aHire"
SKEOF
echo "   Shopkeepers config written"

# ===============================
# SAFETRADE CONFIG
# ===============================
mkdir -p "$PLUGIN_DIR/SafeTrade"
cat > "$PLUGIN_DIR/SafeTrade/config.yml" << 'STEOF'
enabled: true
prefix: "&8[&6Trade&8] "
allow-cross-world: true
request-timeout: 30
gui-title: "&8Safe Trade"
money-trading: false
log-trades: true
log-file: "trades.log"
sounds:
  trade-request: true
  trade-complete: true
  trade-cancel: true
messages:
  trade-request-sent: "&aTrade request sent to &e%player%&a!"
  trade-request-received: "&e%player% &awants to trade! Use &e/trade accept &ato accept."
  trade-accepted: "&aTrade accepted!"
  trade-denied: "&cTrade denied."
  trade-cancelled: "&cTrade cancelled."
  trade-complete: "&aTrade complete!"
  no-pending-request: "&cYou have no pending trade requests."
  already-trading: "&cYou are already in a trade."
  cannot-trade-self: "&cYou cannot trade with yourself."
  player-not-found: "&cPlayer not found."
  player-busy: "&c%player% is busy."
  request-expired: "&cTrade request expired."
STEOF
echo "   SafeTrade config written"

# ===============================
# SKRIPT CONFIG + SCRIPTS
# ===============================
mkdir -p "$PLUGIN_DIR/Skript"
mkdir -p "$PLUGIN_DIR/Skript/scripts"
cat > "$PLUGIN_DIR/Skript/config.sk" << 'SKRIPTEOF'
language: english
color codes: true
script loader:
    use new script loader: true
databases:
    database 1:
        type: CSV
        pattern: .*
        file: ./plugins/Skript/variables.csv
        backup interval: 2 hours
log:
    verbosity: NORMAL
enable effect commands: true
allow function calls from expressions: true
disable variable will not be saved warnings: false
disable missing and/or warnings: false
disable variable conflict warnings: false
date format: default
SKRIPTEOF
echo "   Skript config written"

# ---- PVP core script ----
cat > "$PLUGIN_DIR/Skript/scripts/pvp-core.sk" << 'PVPSKEOF'
# ============================
#  PVP Core — Kills, Penalties, & Downgrades
# ============================

command /setcustomspawn:
    permission: op
    trigger:
        set {serverSpawn} to player's location
        set spawn of world "world" to player's location
        send "&a&lExact spawn point set! Players will now spawn EXACTLY here." to player

on death of player:
    # 1. Update Streaks
    if attacker is a player:
        set {deathsInARow::%attacker%} to 0
        add 1 to {kills::%attacker%}
        send "&c&l☠ &e%victim% &7was slain by &c%attacker% &7(&e%{kills::%attacker%}% kills&7)" to all players
    
    add 1 to {deathsInARow::%victim%}

    # 2. Drop Ores & Currency on the ground (Keep Gear)
    loop all items in victim's inventory:
        if loop-item is coal or iron ore or gold ore or lapis lazuli or redstone or diamond or emerald or cobblestone or stone:
            drop loop-item at victim's location
            remove loop-item from victim's inventory

    # 3. XP Floor Logic (Drop to the bottom of their tier)
    set {_lvl} to victim's level
    if {_lvl} >= 26:
        set victim's level to 26
    else if {_lvl} >= 11:
        set victim's level to 11
    else:
        set victim's level to 0

    # 4. Downgrade Gear Logic (5 Deaths in a row)
    if {deathsInARow::%victim%} >= 5:
        set {deathsInARow::%victim%} to 0
        send "&c&l☠ You died 5 times in a row! Your gear was downgraded!" to victim
        
        # Downgrade Helmet
        if victim's helmet is diamond helmet:
            set victim's helmet to iron helmet
        else if victim's helmet is iron helmet or chainmail helmet:
            set victim's helmet to leather helmet
            
        # Downgrade Chestplate
        if victim's chestplate is diamond chestplate:
            set victim's chestplate to iron chestplate
        else if victim's chestplate is iron chestplate or chainmail chestplate:
            set victim's chestplate to leather chestplate
            
        # Downgrade Leggings
        if victim's leggings is diamond leggings:
            set victim's leggings to iron leggings
        else if victim's leggings is iron leggings or chainmail leggings:
            set victim's leggings to leather leggings
            
        # Downgrade Boots
        if victim's boots is diamond boots:
            set victim's boots to iron boots
        else if victim's boots is iron boots or chainmail boots:
            set victim's boots to leather boots
            
        # Downgrade Pickaxe
        if victim has a diamond pickaxe:
            remove all diamond pickaxes from victim's inventory
            give iron pickaxe to victim
        else if victim has an iron pickaxe:
            remove all iron pickaxes from victim's inventory
            give stone pickaxe to victim

command /stats [<player>]:
    trigger:
        if arg-1 is set:
            set {_target} to arg-1
        else:
            set {_target} to player
        set {_k} to {kills::%{_target}%} ? 0
        set {_d} to {deaths::%{_target}%} ? 0
        send "&8&m                              "
        send "&6&l⚔ &ePVP Stats for &c%{_target}%"
        send "&7Kills: &a%{_k}%"
        send "&7Deaths: &c%{_d}%"
        send "&7Streak: &e%{streak::%{_target}%} ? 0%"
        send "&8&m                              "

on respawn:
    if {serverSpawn} is set:
        set respawn location to {serverSpawn}
    wait 1 tick
    if {serverSpawn} is set:
        teleport player to {serverSpawn}
    if player does not have a sword:
        give player wooden sword named "&7Starter Sword"
    if player does not have a pickaxe:
        give player wooden pickaxe named "&7Starter Pickaxe"

on first join:
    wait 1 tick
    if {serverSpawn} is set:
        teleport player to {serverSpawn}
    give player wooden sword named "&7Starter Sword"
    give player wooden pickaxe named "&7Starter Pickaxe"
    give player 8 of cooked beef named "&6Steak"
    send "&a&lWelcome to the DigPvP!" to player
    send "&7Use &e/stats &7to check your kills and deaths." to player
    send "&7Use &e/trade <player> &7to trade items safely." to player
    send "&7How to play:&7 Mine in the beginner zone to get ores." to player
    send "Buy weapons, tools, armor and more for PVP and mining." to player

on join:
    set join message to "&8[&a+&8] &7%player%"
    wait 5 ticks
    if {serverSpawn} is set:
        teleport player to {serverSpawn}
    else:
        teleport player to spawn of world "world"

on quit:
    set quit message to "&8[&c-&8] &7%player%"

command /spawn:
    trigger:
        # 1. Check if they are in combat
        if {combatTag::%player%} is set:
            if difference between now and {combatTag::%player%} is less than 15 seconds:
                send "&c&lERROR! &7You cannot use /spawn while in combat!" to player
                stop
        
        # 2. Start the 3-second timer
        send "&eTeleporting in 3 seconds... Do not move!" to player
        set {_loc} to player's location
        wait 3 seconds
        
        # 3. Check if they moved
        if distance between player's location and {_loc} > 0.5:
            send "&cTeleport cancelled because you moved!" to player
            stop
            
        # 4. Teleport them safely
        teleport player to spawn of world "world"
        send "&aTeleported to spawn!" to player
PVPSKEOF
echo "   Skript pvp-core.sk written"

# ---- Spawn protection script ----
cat > "$PLUGIN_DIR/Skript/scripts/spawn-protect.sk" << 'SPAWNEOF'
on damage of player:
    attacker is a player
    distance between victim's location and spawn of world "world" is less than 20
    cancel event
    send "&cNo PVP in spawn area!" to attacker
SPAWNEOF
echo "   Skript spawn-protect.sk written"

# ---- Combat tag script ----
cat > "$PLUGIN_DIR/Skript/scripts/combat-tag.sk" << 'COMBATEOF'
on damage of player:
    attacker is a player
    set {combatTag::%victim%} to now
    set {combatTag::%attacker%} to now
    send "&c&l⚔ You are now in combat! Don't log out!" to victim
    send "&c&l⚔ You are now in combat! Don't log out!" to attacker

on quit:
    {combatTag::%player%} is set
    difference between now and {combatTag::%player%} is less than 15 seconds
    kill player
    broadcast "&c%player% combat logged and was killed!"

on region exit:
    # Check if the region they are trying to leave is one of the 3 mines
    if "%region%" contains "beginnermine" or "promine" or "expertmine":
        
        # Check if they are in combat
        if {combatTag::%player%} is set:
            if difference between now and {combatTag::%player%} is less than 15 seconds:
                
                # 1. Cancel their exit (Rubberbands them back inside)
                cancel event
                
                # 2. Push them backward (Knocks them off the ladder/exit back into the pit)
                push player horizontally backward at speed 1.0
                
                # 3. Anti-Spam Message
                if {spamCooldown::%player%} is not set:
                    send "&c&l⚔ &7You cannot escape the mine while in combat!" to player
                    set {spamCooldown::%player%} to now
                else if difference between now and {spamCooldown::%player%} is greater than 2 seconds:
                    send "&c&l⚔ &7You cannot escape the mine while in combat!" to player
                    set {spamCooldown::%player%} to now

every 1 second:
    loop all players:
        {combatTag::%loop-player%} is set
        difference between now and {combatTag::%loop-player%} is greater than 15 seconds
        delete {combatTag::%loop-player%}
COMBATEOF
echo "   Skript combat-tag.sk written"

cat > "$PLUGIN_DIR/Skript/scripts/zones.sk" << 'ZONEEOF'
on region enter:
    # -----------------------------
    # 1. THE BEGINNER MINE (0-20)
    # -----------------------------
    if "%region%" contains "beginnermine":
        if player's level > 20:
            cancel event
            send "&c&lLOCKED! &7You are over Level 20. Use the Pro or Expert Mine!"
            stop

        # Simplified Armor Check
        if player is wearing any iron armor or diamond armor:
            cancel event
            send "&c&lLOCKED! &7Your armor is too strong for the Beginner Mine!"
            stop

    # -----------------------------
    # 2. THE PRO MINE (21-50)
    # -----------------------------
    if "%region%" contains "promine":
        # If level is 20 or less, they stay in beginner
        if player's level <= 20:
            cancel event
            send "&c&lLOCKED! &7You must be Level 21+ for the Pro Mine!"
            stop
            
        # If level is 51 or more, they go to expert
        if player's level > 50:
            cancel event
            send "&c&lLOCKED! &7You are over Level 50. Use the Expert Mine!"
            stop

        if player is wearing any diamond armor:
            cancel event
            send "&c&lLOCKED! &7Your armor is too strong for the Pro Mine!"
            stop

    # -----------------------------
    # 3. THE EXPERT MINE (51+)
    # -----------------------------
    if "%region%" contains "expertmine":
        if player's level <= 50:
            cancel event
            send "&c&lLOCKED! &7You need to be Level 51+ to enter!"
            
ZONEEOF
echo "   Skript spawn-protect.sk written"

# ---- Emerald economy script ----
cat > "$PLUGIN_DIR/Skript/scripts/economy.sk" << 'ECONEOF'
command /balance [<player>]:
    aliases: /bal, /money
    trigger:
        if arg-1 is set:
            set {_target} to arg-1
        else:
            set {_target} to player
        set {_emeralds} to number of emeralds in {_target}'s inventory
        send "&8&m                              "
        send "&6&l$ &eBalance for &c%{_target}%"
        send "&7Emeralds: &a%{_emeralds}%"
        send "&8&m                              "

command /pay <player> <integer>:
    trigger:
        if arg-2 is less than 1:
            send "&cAmount must be at least 1!"
            stop
        if arg-1 is player:
            send "&cYou can't pay yourself!"
            stop
        set {_has} to number of emeralds in player's inventory
        if {_has} is less than arg-2:
            send "&cYou don't have enough emeralds!"
            stop
        remove arg-2 of emerald from player's inventory
        give arg-2 of emerald to arg-1
        send "&aSent &e%arg-2% emeralds &ato &e%arg-1%&a!"
        send "&a%player% &esent you &a%arg-2% emeralds&e!" to arg-1
ECONEOF
echo "   Skript economy.sk written"

echo ""
echo "   All configs written — reloading plugins via RCON..."

# ===============================
# RELOAD ALL PLUGINS so configs take effect
# ===============================
sleep 2
mc_command "worldguard reload"
echo "   WorldGuard reloaded"
mc_command "skript reload all"
echo "   Skript scripts reloaded"
mc_command "worldedit reload"
echo "   WorldEdit reloaded"
mc_command "reload confirm"
echo "   Full server reload done — all plugin configs applied"
echo ""

# =============================================================
# STEP 6: EaglerXBungee generation + Start BungeeCord
# =============================================================
LISTENERS_FILE=$(find_listeners_yml)

if [ -z "$LISTENERS_FILE" ]; then
    echo "[6/7] Generating EaglerXBungee config..."
    cd "$BUNGEE_DIR"
    $JAVA "${BUNGEE_JVM_FLAGS[@]}" \
        -cp "sqlite-jdbc.jar:BungeeCord.jar" \
        net.md_5.bungee.Bootstrap >> /tmp/bungee-gen.log 2>&1 &
    GEN_PID=$!

    for i in $(seq 1 60); do
        if nc -z 127.0.0.1 8081 2>/dev/null || nc -z 127.0.0.1 7860 2>/dev/null; then
            echo " EaglerXBungee started (~$((i*2))s)"
            break
        fi
        if ! kill -0 $GEN_PID 2>/dev/null; then
            echo " Generation failed"
            tail -20 /tmp/bungee-gen.log
            break
        fi
        sleep 2
    done

    sleep 3
    kill $GEN_PID 2>/dev/null
    wait $GEN_PID 2>/dev/null
    for i in $(seq 1 15); do
        nc -z 127.0.0.1 8081 2>/dev/null || break
        sleep 1
    done
    sleep 2
else
    echo "[6/7] EaglerXBungee config exists"
fi

echo " Starting BungeeCord..."

patch_eagler_port

# === NEW: MOTD AND ICON PATCH ===
LISTENERS_NOW=$(find_listeners_yml)
if [ -n "$LISTENERS_NOW" ]; then
    # This adds the randomizing characters (&k) at the start and end of the title
    # &k!!&r makes the exclamation marks cycle randomly, then &r stops the randomization
    sed -i 's/An EaglercraftX server/&6&k!!&r &6&l⚔ DIG PVP ⚔ &6&k!!&r &7- &eBoxPvP/g' "$LISTENERS_NOW"
    
    # You can also add it to the subtitle if you want
    sed -i 's/EaglercraftX proxy/&a&k#&r &fMine ores, buy gear, fight! &a&k#&r/g' "$LISTENERS_NOW"
fi

# Copy the server icon from your HuggingFace bucket to BungeeCord
if [ -f "$BACKEND_DIR/server-icon.png" ]; then
    cp -f "$BACKEND_DIR/server-icon.png" "$BUNGEE_DIR/server-icon.png"
fi
# ================================

EAGLER_DIR=$(dirname "$(find_listeners_yml)" 2>/dev/null)

EAGLER_DIR=$(dirname "$(find_listeners_yml)" 2>/dev/null)
if [ -n "$EAGLER_DIR" ]; then
    mkdir -p "$EAGLER_DIR/drivers"
    cp -f "$BUNGEE_DIR/sqlite-jdbc.jar" "$EAGLER_DIR/drivers/sqlite-jdbc.jar" 2>/dev/null
fi

> /tmp/bungee.log
start_bungee
echo " BungeeCord PID: $BUNGEE_PID"

PORT_READY=false
for i in $(seq 1 45); do
    if nc -z 127.0.0.1 7860 2>/dev/null; then
        PORT_READY=true
        echo " Port 7860 OPEN (~$((i*2))s)"
        break
    fi
    if ! kill -0 $BUNGEE_PID 2>/dev/null; then
        echo " BungeeCord crashed!"
        tail -20 /tmp/bungee.log
        break
    fi
    sleep 2
done

if [ "$PORT_READY" = true ]; then
    echo ""
    echo "============================================"
    echo " PVP SERVER READY — EaglerCraft on :7860"
    [ -n "$OP_USERNAME" ] && echo " OP: $OP_USERNAME (level 4)"
    echo " Plugins: WE, WG, MRL, Shopkeepers, SafeTrade, Skript"
    echo "============================================"
else
    echo " Port 7860 NOT open!"
    for port in 7860 8081 25565 25577; do
        nc -z 127.0.0.1 $port 2>/dev/null && echo "   OK $port" || echo "   FAIL $port"
    done
    LISTENERS_NOW=$(find_listeners_yml)
    if [ -n "$LISTENERS_NOW" ] && grep -q ":8081" "$LISTENERS_NOW"; then
        kill $BUNGEE_PID 2>/dev/null
        wait $BUNGEE_PID 2>/dev/null
        sleep 3
        patch_eagler_port
        start_bungee
        sleep 20
        nc -z 127.0.0.1 7860 2>/dev/null && echo " Port 7860 open!" || echo " Failed"
    fi
fi

# =============================================================
# STEP 7: Final confirmation
# =============================================================
echo ""
echo "[7/7] Final status check..."
echo " === ACTIVE PLUGINS ==="
RELOAD_CHECK=$(mc_command "plugins")
echo "   $RELOAD_CHECK"
echo " ======================"
echo ""

# =============================================================
# Sync loop
# =============================================================
hf_sync_loop &
SYNC_PID=$!

# =============================================================
# Shutdown — save world properly, then push, then stop processes
# =============================================================
graceful_shutdown() {
    echo " Shutting down..."
    mc_command "gamerule doMobSpawning true"
    mc_command "gamerule randomTickSpeed 3"
    mc_command "save-all"
    sleep 5
    hf_push_saves
    kill $SYNC_PID 2>/dev/null
    # Stop the MC server gracefully via RCON before killing PIDs
    mc_command "stop"
    sleep 5
    kill $BUNGEE_PID 2>/dev/null
    # Only force-kill if still alive
    kill -0 $BACKEND_PID 2>/dev/null && kill $BACKEND_PID 2>/dev/null
    exit 0
}

trap graceful_shutdown SIGTERM SIGINT SIGHUP

# =============================================================
# Monitor loop
# =============================================================
echo ""
echo "Monitor loop started..."

LAST_LOG_LINE=$(wc -l < /tmp/paper.log 2>/dev/null || echo 0)
LOOP_COUNT=0

while true; do
    LOOP_COUNT=$((LOOP_COUNT + 1))

    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] WindSpigot crashed — restarting..."
        hf_push_saves
        IDLE_MODE=false
        start_windspigot
        sleep 45
        # Wait for RCON to be available before sending commands
        for i in $(seq 1 30); do
            nc -z 127.0.0.1 25575 2>/dev/null && break
            sleep 1
        done
        if [ -n "$OP_USERNAME" ]; then
            mc_command "op ${OP_USERNAME}"
        fi
        mc_command "gamerule pvp true"
        mc_command "gamerule keepInventory false"
        mc_command "gamerule mobGriefing false"
        enter_idle_mode
    fi

    if ! kill -0 $BUNGEE_PID 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] BungeeCord crashed — restarting..."
        patch_eagler_port
        start_bungee
    fi

    if ! kill -0 $SYNC_PID 2>/dev/null; then
        hf_sync_loop &
        SYNC_PID=$!
    fi

    if kill -0 $BACKEND_PID 2>/dev/null; then
        PLAYER_COUNT=$(get_player_count)
        if [ "$PLAYER_COUNT" != "0" ] && [ "$IDLE_MODE" = true ]; then
            exit_idle_mode
        elif [ "$PLAYER_COUNT" = "0" ] && [ "$IDLE_MODE" = false ]; then
            enter_idle_mode
        fi
    fi

    if [ $((LOOP_COUNT % 5)) -eq 0 ]; then
        CURRENT_LINE=$(wc -l < /tmp/paper.log 2>/dev/null || echo 0)
        if [ "$CURRENT_LINE" -gt "$LAST_LOG_LINE" ]; then
            NEW_ERRORS=$(tail -n +"$((LAST_LOG_LINE + 1))" /tmp/paper.log | grep -c "ERROR\|SEVERE" || echo 0)
            [ "$NEW_ERRORS" -gt 0 ] && echo "[$(date '+%H:%M:%S')] $NEW_ERRORS errors" && \
                tail -n +"$((LAST_LOG_LINE + 1))" /tmp/paper.log | grep "ERROR\|SEVERE" | tail -3
            LAST_LOG_LINE=$CURRENT_LINE
        fi
    fi

    if [ $((LOOP_COUNT % 30)) -eq 0 ]; then
        for LF in /tmp/paper.log /tmp/bungee.log; do
            LS=$(stat -c%s "$LF" 2>/dev/null || echo 0)
            if [ "$LS" -gt 10485760 ]; then
                tail -1000 "$LF" > "${LF}.tmp" && mv "${LF}.tmp" "$LF"
                echo "[$(date '+%H:%M:%S')] Trimmed $(basename $LF)"
            fi
        done
        LAST_LOG_LINE=$(wc -l < /tmp/paper.log 2>/dev/null || echo 0)
    fi

    if [ $((LOOP_COUNT % 5)) -eq 0 ]; then
        RSS=$(ps -p $BACKEND_PID -o rss= 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        echo "[STATUS] Players: ${PLAYER_COUNT:-?} | RAM: ${RSS:-?}MB | $([ "$IDLE_MODE" = true ] && echo IDLE || echo ACTIVE)"
    fi

    sleep 60
done
