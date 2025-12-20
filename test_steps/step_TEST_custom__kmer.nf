nextflow.enable.dsl=2

/*
 * Custom step example: k-mer analysis with k=17
 * 
 * Simple example using an existing Docker container to count k-mers
 */

include { getInput } from '../functions/parameters.nf'
include { parseMetadataFromFileName; executionMetadata } from '../functions/common.nf'

def ex = executionMetadata()

def STEP = 'TEST_custom'
def METHOD = 'kmer'

// Simple k-mer counting process using seqtk (lightweight, widely available)
process kmer_count {
    // Docker container from Docker Hub - Nextflow will download it automatically
    container "staphb/seqtk:latest"
    // Available at: https://hub.docker.com/r/staphb/seqtk
    // Note: Requires Docker permissions. If you get permission errors, run:
    //   sudo usermod -aG docker $USER
    //   newgrp docker
    
    publishDir mode: 'copy', "${params.outdir}/${md.anno}/${md.cmp}/${STEP}/${md.ds}-${ex.dt}_${METHOD}/result"
    
    input:
    tuple val(riscd_input), path(reads)
    
    output:
    path "kmer_stats.txt"
    path "*.log", hidden: true
    
    script:
    (r1,r2) = (reads instanceof java.util.Collection) ? reads : [reads, null]
    md = parseMetadataFromFileName(r1.getName())
    base = "${md.ds}-${ex.dt}_${md.cmp}_${METHOD}"
    k = 17
    
    """
    echo "=== K-mer Analysis (k=${k}) ===" > kmer_stats.txt
    echo "Sample: ${md.cmp}" >> kmer_stats.txt
    echo "DS: ${md.ds}" >> kmer_stats.txt
    echo "DT: ${ex.dt}" >> kmer_stats.txt
    echo "" >> kmer_stats.txt
    
    echo "Processing R1: ${r1.getName()}" >> kmer_stats.txt
    echo "File size:" >> kmer_stats.txt
    ls -lh ${r1} >> kmer_stats.txt 2>&1 || echo "N/A" >> kmer_stats.txt
    echo "" >> kmer_stats.txt
    
    ${r2 ? """
    echo "Processing R2: ${r2.getName()}" >> kmer_stats.txt
    echo "File size:" >> kmer_stats.txt
    ls -lh ${r2} >> kmer_stats.txt 2>&1 || echo "N/A" >> kmer_stats.txt
    echo "" >> kmer_stats.txt
    echo "Paired-end reads detected" >> kmer_stats.txt
    """ : """
    echo "Single-end reads detected" >> kmer_stats.txt
    """}
    
    echo "" >> kmer_stats.txt
    echo "K-mer size: ${k}" >> kmer_stats.txt
    echo "Analysis completed: \$(date)" >> kmer_stats.txt
    
    # Simple k-mer extraction example (first 1000 bases) using seqtk from container
    echo "Extracting sample k-mers (first 1000 bases)..." >> kmer_stats.txt
    seqtk seq -A ${r1} 2>/dev/null | head -c 1000 | grep -o . | paste - - - - - - - - - - - - - - - - - | head -1 >> kmer_stats.txt 2>&1 || echo "K-mer extraction skipped" >> kmer_stats.txt
    
    echo "Done" > ${base}.log
    """
}

workflow {
    reads = getInput()
    kmer_count(reads)
}

