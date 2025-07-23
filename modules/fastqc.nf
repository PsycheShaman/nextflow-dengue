/*
 * -------------------------------------------------
 *  FastQC Process Module
 * -------------------------------------------------
 * 
 * This module runs FastQC on input reads to generate quality control reports.
 * FastQC performs quality control checks on raw sequence data coming from 
 * high throughput sequencing pipelines.
 */

// Process Definition
process FASTQC {
    // Process Tags
    tag "$meta.id"      // Tag process with sample ID for logging
    label 'process_low' // Use low resource requirements

    // Conda Environment
    // Use FastQC from the bioconda channel
    conda "bioconda::fastqc=0.11.9"

    // Container Definition
    // Use either Singularity or Docker container based on workflow configuration
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastqc:0.11.9--0' :
        'biocontainers/fastqc:0.11.9--0' }"

    // Input Definition
    input:
    tuple val(meta), path(reads)  // Tuple of metadata and read files
                                 // meta: Map containing sample information
                                 // reads: FastQ file(s) to analyze

    // Output Definition
    output:
    tuple val(meta), path("*.html"), emit: html  // HTML report files
    tuple val(meta), path("*.zip") , emit: zip   // ZIP archives of results
    path  "versions.yml"           , emit: versions  // Software versions for provenance

    // Process Control
    when:
    task.ext.when == null || task.ext.when  // Only run if when clause is satisfied

    // Main Script
    script:
    // Define optional arguments
    def args = task.ext.args ?: ''  // Custom arguments from pipeline config
    def prefix = task.ext.prefix ?: "${meta.id}"  // Output prefix, default to sample ID

    // FastQC command
    """
    # Run FastQC with specified parameters
    fastqc $args --threads $task.cpus $reads

    # Record software versions for reproducibility
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: \$( fastqc --version | sed -e "s/FastQC v//g" )
    END_VERSIONS
    """

    /*
     * Process Explanation:
     * 1. FastQC is run on input reads with specified number of threads
     * 2. Generates HTML reports and ZIP archives containing:
     *    - Basic Statistics
     *    - Per base sequence quality
     *    - Per sequence quality scores
     *    - Per base sequence content
     *    - Per sequence GC content
     *    - Per base N content
     *    - Sequence Length Distribution
     *    - Sequence Duplication Levels
     *    - Overrepresented sequences
     *    - Adapter Content
     * 3. Version information is saved for reproducibility
     */
} 