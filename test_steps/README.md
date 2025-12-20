# Test Custom Step

⚠️ **FOR TESTING PURPOSES ONLY**

This file () is a test custom step example.

## Usage

To use this test step, **move it to the  directory**:

```bash
cp test_steps/step_TEST_custom__kmer.nf cohesive-ngsmanager/steps/
```

Then run it with:

```bash
./ngsmanager_run.sh cohesive-ngsmanager/steps/step_TEST_custom__kmer.nf \
  R1.fastq.gz R2.fastq.gz \
  --no-timeout \
  --outdir /mnt/data/results
```

## Description

- **Purpose**: Test custom step example
- **Function**: K-mer analysis with k=17
- **Container**: staphb/seqtk:latest (from Docker Hub)
- **Location**: Should be moved to `cohesive-ngsmanager/steps/` for use

This is an example to demonstrate how to create custom Nextflow steps for NGSManager CLI.

