#!/bin/bash
#
# ngsmanager_run.sh - Script to run NGSManager steps from CLI
#
# This script automatically prepares the directory structure and file names
# in the format required by NGSManager, then launches the Nextflow step.
#
# REQUIREMENTS:
#   - nextflow (install with: curl -s https://get.nextflow.io | bash)
#   - docker
#
# USAGE:
#   ./ngsmanager_run.sh <step.nf> <R1.fastq.gz> [R2.fastq.gz] [options...]
#
# EXAMPLES:
#   # Fastp on paired-end
#   ./ngsmanager_run.sh step_1PP_trimming__fastp.nf sample_R1.fastq.gz sample_R2.fastq.gz
#
#   # Fastp on single-end (ion torrent)
#   ./ngsmanager_run.sh step_1PP_trimming__fastp.nf sample.fastq.gz --seq_type ion
#
#   # With extra parameters for resfinder
#   ./ngsmanager_run.sh step_4AN_AMR__resfinder.nf R1.fq.gz R2.fq.gz --genus_species Salmonella_enterica
#
# ENVIRONMENT VARIABLES:
#   NGSMANAGER_DIR  Path to cohesive-ngsmanager (required if not in ./cohesive-ngsmanager)
#   WORKDIR         Working directory (default: ./ngsmanager_workdir)
#   NEXTFLOW        Path to nextflow (default: searches in PATH or ~/.local/bin)
#

set -e

# === CONFIGURATION ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find ngsmanager
if [ -n "$NGSMANAGER_DIR" ]; then
    :
elif [ -d "$SCRIPT_DIR/cohesive-ngsmanager" ]; then
    NGSMANAGER_DIR="$SCRIPT_DIR/cohesive-ngsmanager"
elif [ -d "./cohesive-ngsmanager" ]; then
    NGSMANAGER_DIR="./cohesive-ngsmanager"
else
    echo "Error: NGSMANAGER_DIR not set and cohesive-ngsmanager not found"
    echo "Set: export NGSMANAGER_DIR=/path/to/cohesive-ngsmanager"
    exit 1
fi
NGSMANAGER_DIR=$(realpath "$NGSMANAGER_DIR")

# Working directory
WORKDIR="${WORKDIR:-$(pwd)/ngsmanager_workdir}"

# Find nextflow
if [ -n "$NEXTFLOW" ] && [ -x "$NEXTFLOW" ]; then
    :
elif command -v nextflow &> /dev/null; then
    NEXTFLOW=$(command -v nextflow)
elif [ -x "$HOME/.local/bin/nextflow" ]; then
    NEXTFLOW="$HOME/.local/bin/nextflow"
else
    echo "Error: nextflow not found"
    echo "Install with: curl -s https://get.nextflow.io | bash && mv nextflow ~/.local/bin/"
    exit 1
fi

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# === FUNCTIONS ===
usage() {
    echo -e "${CYAN}NGSManager CLI Runner${NC}"
    echo ""
    echo "Usage: $0 <step.nf> <R1.fastq.gz> [R2.fastq.gz] [options...]"
    echo ""
    echo -e "${YELLOW}Available steps:${NC}"
    ls -1 "$NGSMANAGER_DIR/steps/" 2>/dev/null | grep '\.nf$' | sed 's/^/  /'
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --seq_type TYPE       illumina_paired|ion|nanopore (default: auto)"
    echo "  --genus_species SP    E.g.: Salmonella_enterica (required for some steps)"
    echo "  --cmp CODE            Sample code (default: auto-generated)"
    echo "  --resume              Resume previous execution"
    echo "  [other parameters]    Passed directly to nextflow"
    echo ""
    echo -e "${YELLOW}Environment variables:${NC}"
    echo "  NGSMANAGER_DIR=$NGSMANAGER_DIR"
    echo "  WORKDIR=$WORKDIR"
    echo "  NEXTFLOW=$NEXTFLOW"
    echo ""
    echo -e "${YELLOW}Full example:${NC}"
    echo "  $0 step_1PP_trimming__fastp.nf reads_R1.fastq.gz reads_R2.fastq.gz"
    exit 1
}

# === ARGUMENT PARSING ===
if [ $# -lt 2 ]; then
    usage
fi

STEP="$1"
R1="$2"
shift 2

# Find the .nf file
if [ -f "$STEP" ]; then
    STEP_FILE="$STEP"
elif [ -f "$NGSMANAGER_DIR/steps/$STEP" ]; then
    STEP_FILE="$NGSMANAGER_DIR/steps/$STEP"
elif [ -f "$NGSMANAGER_DIR/steps/step_${STEP}.nf" ]; then
    STEP_FILE="$NGSMANAGER_DIR/steps/step_${STEP}.nf"
else
    echo -e "${RED}Error: Step '$STEP' not found${NC}"
    echo ""
    usage
fi

# Verify R1
if [ ! -f "$R1" ]; then
    echo -e "${RED}Error: File '$R1' not found${NC}"
    exit 1
fi
R1=$(realpath "$R1")

# Check if there's R2 (if next argument doesn't start with --)
R2=""
SEQ_TYPE="illumina_paired"
if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    if [ -f "$1" ]; then
        R2="$1"
        R2=$(realpath "$R2")
        shift
    else
        # Not a file, might be an option without --
        SEQ_TYPE="ion"
    fi
else
    SEQ_TYPE="ion"
fi

# If we have R2, it's paired-end
[ -n "$R2" ] && SEQ_TYPE="illumina_paired"

# Parse extra options
EXTRA_OPTS=""
CMP=""
RESUME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seq_type)
            SEQ_TYPE="$2"
            shift 2
            ;;
        --cmp)
            CMP="$2"
            shift 2
            ;;
        --resume)
            RESUME="-resume"
            shift
            ;;
        *)
            EXTRA_OPTS="$EXTRA_OPTS $1"
            shift
            ;;
    esac
done

# === GENERATE IDENTIFIERS ===
YEAR=$(date +%Y)
DT=$(date +%y%m%d)
# Use a hash of the filename to have consistent DS for the same file
DS=$(echo "$R1" | md5sum | cut -c1-5 | tr 'a-f' '0-5')
DS=$(printf "%05d" $((16#$DS % 99999 + 1)))

if [ -z "$CMP" ]; then
    CMP="${YEAR}.CLI.${DS}.1.1"
fi

# Input ACC and METHOD (always rawreads/import for input)
INPUT_ACC="0SQ_rawreads"
INPUT_METHOD="import"

RISCD="${DT}-${DS}-${INPUT_ACC}-${INPUT_METHOD}"

# Extract ENTRYPOINT from step filename (e.g., step_1PP_trimming__fastp.nf -> step_1PP_trimming__fastp)
STEP_BASENAME=$(basename "$STEP_FILE" .nf)

# === OUTPUT INFO ===
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}              ${CYAN}NGSManager CLI Runner${NC}                          ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Step:${NC}       $(basename $STEP_FILE)"
echo -e "${YELLOW}CMP:${NC}        $CMP"
echo -e "${YELLOW}RISCD:${NC}      $RISCD"
echo -e "${YELLOW}Seq type:${NC}   $SEQ_TYPE"
echo -e "${YELLOW}Input R1:${NC}   $R1"
[ -n "$R2" ] && echo -e "${YELLOW}Input R2:${NC}   $R2"
[ -n "$EXTRA_OPTS" ] && echo -e "${YELLOW}Extra:${NC}      $EXTRA_OPTS"
echo ""

# === CREATE DIRECTORY STRUCTURE ===
INPUT_DIR="$WORKDIR/inputdir/$YEAR/$CMP/$INPUT_ACC/DS${DS}-DT${DT}_${INPUT_METHOD}/result"
OUTPUT_DIR="$WORKDIR/results"
WORK_DIR="$WORKDIR/work"
TMP_DIR="$WORKDIR/.tmp"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR" "$TMP_DIR"

# Create symbolic links to files with correct naming
DEST_R1="$INPUT_DIR/DS${DS}-DT${DT}_${CMP}_R1.fastq.gz"
ln -sf "$R1" "$DEST_R1"

if [ -n "$R2" ]; then
    DEST_R2="$INPUT_DIR/DS${DS}-DT${DT}_${CMP}_R2.fastq.gz"
    ln -sf "$R2" "$DEST_R2"
fi

echo -e "${GREEN}Input structure created:${NC}"
echo "  $INPUT_DIR/"
ls -la "$INPUT_DIR/" | tail -n +2 | sed 's/^/    /'
echo ""

# === GENERATE CLI CONFIG ===
# This config mounts the scripts directory to fix the containerOptions issue
# Note: If the step already has containerOptions with /scripts mount, we don't add it here to avoid duplicate mount
SCRIPTS_DIR="$NGSMANAGER_DIR/scripts/$STEP_BASENAME"
CLI_CONFIG="$WORKDIR/cli.config"

# Check if step already has containerOptions with /scripts mount
HAS_SCRIPTS_MOUNT=$(grep -q "containerOptions.*:/scripts" "$STEP_FILE" 2>/dev/null && echo "yes" || echo "no")

if [ -d "$SCRIPTS_DIR" ] && [ "$HAS_SCRIPTS_MOUNT" = "no" ]; then
    cat > "$CLI_CONFIG" << EOF
// Auto-generated CLI config - mounts scripts directory for container processes
docker {
    enabled = true
    runOptions = "-u \\\$(id -u):\\\$(id -g) --memory-swappiness 0 --cpus 64 -v ${SCRIPTS_DIR}:/scripts:ro"
    fixOwnership = true
}
EOF
    echo -e "${GREEN}Generated CLI config:${NC} $CLI_CONFIG"
    echo -e "  Scripts mount: ${YELLOW}${SCRIPTS_DIR}:/scripts${NC}"
    echo ""
    CONFIG_OPT="-c $CLI_CONFIG"
elif [ "$HAS_SCRIPTS_MOUNT" = "yes" ]; then
    # Step already has containerOptions with /scripts, just set basic docker config without mount
    cat > "$CLI_CONFIG" << EOF
// Auto-generated CLI config - step already has containerOptions with /scripts mount
docker {
    enabled = true
    runOptions = "-u \\\$(id -u):\\\$(id -g) --memory-swappiness 0 --cpus 64"
    fixOwnership = true
}
EOF
    echo -e "${GREEN}Generated CLI config:${NC} $CLI_CONFIG"
    echo -e "${YELLOW}Note:${NC} Step already has containerOptions with /scripts mount, using it"
    echo ""
    CONFIG_OPT="-c $CLI_CONFIG"
else
    echo -e "${YELLOW}Note:${NC} No scripts directory found for this step, skipping config generation"
    echo ""
    CONFIG_OPT=""
fi

# === CONFIGURE ENVIRONMENT ===
export NXF_TEMP="$TMP_DIR"
export TMPDIR="$TMP_DIR"
export NXF_HOME="$WORKDIR/.nextflow"

# === BUILD COMMAND ===
NF_CMD="$NEXTFLOW run $STEP_FILE \
  $CONFIG_OPT \
  --cmp $CMP \
  --riscd $RISCD \
  --seq_type $SEQ_TYPE \
  --inputdir $WORKDIR/inputdir \
  --outdir $OUTPUT_DIR \
  -work-dir $WORK_DIR \
  $RESUME \
  $EXTRA_OPTS"

echo -e "${GREEN}Command:${NC}"
echo "$NF_CMD" | fold -s -w 80 | sed 's/^/  /'
echo ""

# === EXECUTE ===
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Starting pipeline...${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

eval $NF_CMD
EXIT_CODE=$?

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✔ Completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠ Completed with warnings/errors (exit code: $EXIT_CODE)${NC}"
fi
echo ""
echo -e "${YELLOW}Output:${NC} $OUTPUT_DIR/$YEAR/$CMP/"
echo ""
echo -e "${CYAN}Generated files:${NC}"
find "$OUTPUT_DIR" -type l -o -type f 2>/dev/null | sort | sed 's|.*/results/|  results/|'

exit $EXIT_CODE
