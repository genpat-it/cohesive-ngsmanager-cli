# NGSManager CLI

> ⚠️ **Work in Progress**: This project is under active development. Features may change and improvements are ongoing. Feedback and contributions are welcome!

Command-line tools for running [cohesive-ngsmanager](https://github.com/genpat-it/cohesive-ngsmanager) pipelines without Jenkins.

## Prerequisites

- **Linux** (tested on AlmaLinux/RHEL)
- **Docker** installed and running
- **Java 11+** (required by Nextflow)
- **cohesive-ngsmanager** repository cloned locally

## Installation

### 1. Clone this repository

```bash
git clone https://github.com/genpat-it/cohesive-ngsmanager-cli.git
cd cohesive-ngsmanager-cli
chmod +x ngsmanager_run.sh
```

### 2. Clone cohesive-ngsmanager

```bash
git clone https://github.com/genpat-it/cohesive-ngsmanager.git
```

### 3. Install Nextflow

```bash
curl -s https://get.nextflow.io | bash
mv nextflow ~/.local/bin/
# Or: sudo mv nextflow /usr/local/bin/

# Verify
nextflow -version
```

## Quick Start

```bash
# Set the path to ngsmanager (if not in current directory)
export NGSMANAGER_DIR=/path/to/cohesive-ngsmanager

# Run fastp on paired-end files
./ngsmanager_run.sh step_1PP_trimming__fastp.nf reads_R1.fastq.gz reads_R2.fastq.gz

# Results will be in ./ngsmanager_workdir/results/
```

## Usage

```bash
./ngsmanager_run.sh <step.nf> <R1.fastq.gz> [R2.fastq.gz] [options...]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--seq_type TYPE` | Sequencing type: `illumina_paired`, `ion`, `nanopore` | Auto-detect |
| `--genus_species SP` | Species (e.g.: `Salmonella_enterica`) | - |
| `--cmp CODE` | Custom sample code | Auto-generated |
| `--resume` | Resume interrupted execution | - |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NGSMANAGER_DIR` | Path to cohesive-ngsmanager | `./cohesive-ngsmanager` |
| `WORKDIR` | Working directory | `./ngsmanager_workdir` |
| `NEXTFLOW` | Path to nextflow | Searches in PATH |

## Examples

### Paired-end Illumina trimming

```bash
./ngsmanager_run.sh step_1PP_trimming__fastp.nf sample_R1.fastq.gz sample_R2.fastq.gz
```

### Single-end Ion Torrent

```bash
./ngsmanager_run.sh step_1PP_trimming__fastp.nf sample.fastq.gz --seq_type ion
```

### AMR analysis with species

```bash
./ngsmanager_run.sh step_4AN_AMR__resfinder.nf R1.fq.gz R2.fq.gz \
    --genus_species Salmonella_enterica
```

### Resume failed execution

```bash
./ngsmanager_run.sh step_1PP_trimming__fastp.nf R1.fq.gz R2.fq.gz --resume
```

### Custom working directory

```bash
WORKDIR=/data/analysis ./ngsmanager_run.sh step_1PP_trimming__fastp.nf R1.fq.gz R2.fq.gz
```

## Available Steps

Run `./ngsmanager_run.sh` without arguments to see all available steps.

Common steps:

| Step | Description |
|------|-------------|
| `step_1PP_trimming__fastp.nf` | Quality trimming with fastp |
| `step_1PP_trimming__trimmomatic.nf` | Trimming with Trimmomatic |
| `step_2AS_denovo__spades.nf` | De novo assembly with SPAdes |
| `step_2AS_denovo__shovill.nf` | De novo assembly with Shovill |
| `step_3TX_class__kraken2.nf` | Taxonomic classification |
| `step_4AN_AMR__resfinder.nf` | AMR detection with ResFinder |
| `step_4AN_AMR__abricate.nf` | AMR detection with Abricate |
| `step_4TY_MLST__mlst.nf` | MLST typing |

## Output Structure

```
ngsmanager_workdir/
└── results/
    └── {YEAR}/
        └── {CMP}/
            └── {STEP}/
                └── {DS}-{DT}_{METHOD}/
                    ├── result/      # Main outputs (FASTQ, FASTA, etc.)
                    ├── meta/        # Metadata (JSON, log, config)
                    └── qc/          # Quality reports
```

## Troubleshooting

### "No space left on device"

The script automatically uses a local `.tmp` directory (inside `WORKDIR`) to avoid issues with a full `/tmp` or root filesystem. It sets:
- `NXF_TEMP` and `TMPDIR` to `./ngsmanager_workdir/.tmp`
- `NXF_HOME` to `./ngsmanager_workdir/.nextflow`

If you still encounter disk space issues:

1. **Use a custom working directory** on a partition with more space:
   ```bash
   WORKDIR=/data/myanalysis ./ngsmanager_run.sh step_1PP_trimming__fastp.nf R1.fq.gz R2.fq.gz
   ```

2. **Clean up previous runs**:
   ```bash
   rm -rf ./ngsmanager_workdir/work ./ngsmanager_workdir/.tmp ./ngsmanager_workdir/.nextflow
   ```

3. **Clean Docker** to free up space:
   ```bash
   docker system prune -af
   ```

### "unexpected file name" or "unexpected RISCD format"

The script handles naming conventions automatically. If you see this error, ensure you're using the latest version of the script.

### Pipeline interrupted

Resume with `--resume`:

```bash
./ngsmanager_run.sh step_1PP_trimming__fastp.nf R1.fq.gz R2.fq.gz --resume
```

## License

See [cohesive-ngsmanager](https://github.com/genpat-it/cohesive-ngsmanager) for license information.
