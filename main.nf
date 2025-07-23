#!/usr/bin/env nextflow

// Enable DSL2 syntax - this is required for using modules and modern Nextflow features
// DSL2 provides better code organization and reusability compared to DSL1
nextflow.enable.dsl = 2

/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

// Create a summary of parameters using nf-core's schema functionality
// This will be used in the completion email and summary
def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Initialize the workflow with parameter validation
// This comes from nf-core templates and checks if parameters meet requirements
WorkflowMain.initialise(params, log)

// Check if input files/paths exist before running the pipeline
// This prevents the pipeline from running if inputs are missing
def checkPathParamList = [ params.input, params.genome ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

/*
========================================================================================
    IMPORT LOCAL MODULES/SUBWORKFLOWS
========================================================================================
*/

// Import process modules
// Each module contains a single step of the pipeline
// The 'include' statement makes the process available in this workflow
include { FASTQC }         from './modules/fastqc'           // Quality control of raw reads
include { MULTIQC }        from './modules/multiqc'         // Aggregate QC reports
include { BWA_INDEX }      from './modules/bwa/index'       // Index reference genome
include { BWA_ALIGN }      from './modules/bwa/align'       // Align reads to reference
include { SAMTOOLS_SORT }  from './modules/samtools/sort'   // Sort BAM by coordinates
include { SAMTOOLS_INDEX } from './modules/samtools/index'  // Index BAM for random access
include { BCFTOOLS_CALL }  from './modules/bcftools/call'   // Call variants from BAM

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

// Main workflow definition
workflow {
    // STEP 0: Set up input channels
    // Create a channel for input reads using fromFilePairs
    // This looks for paired-end reads with patterns like: sample_1.fastq.gz, sample_2.fastq.gz
    ch_input_reads = Channel
        .fromFilePairs(params.input, checkIfExists: true)
        .ifEmpty { exit 1, "Cannot find any reads matching: ${params.input}\nNB: Path needs to be enclosed in quotes!" }

    // Create a channel for the reference genome
    // Using value() because the genome file will be reused multiple times
    ch_genome = Channel
        .value(file(params.genome))

    // STEP 1: Quality Control
    // Run FastQC on raw reads to assess quality
    // Output includes HTML reports and ZIP files with detailed metrics
    FASTQC(ch_input_reads)

    // STEP 2: Index Reference Genome
    // Create BWA index files required for alignment
    // This only needs to be done once per reference genome
    BWA_INDEX(ch_genome)

    // STEP 3: Align Reads
    // Map reads to the reference genome using BWA
    // Uses both the input reads and the index files from BWA_INDEX
    BWA_ALIGN(ch_input_reads, BWA_INDEX.out.index)

    // STEP 4: Sort BAM
    // Sort the BAM file by coordinates
    // Required for most downstream tools and efficient access
    SAMTOOLS_SORT(BWA_ALIGN.out.bam)

    // STEP 5: Index BAM
    // Create BAI index for random access to BAM
    // Required for efficient variant calling
    SAMTOOLS_INDEX(SAMTOOLS_SORT.out.bam)

    // STEP 6: Variant Calling
    // Call variants using BCFtools
    // Requires sorted BAM, its index, and the reference genome
    BCFTOOLS_CALL(
        SAMTOOLS_SORT.out.bam,
        SAMTOOLS_INDEX.out.bai,
        ch_genome
    )

    // STEP 7: MultiQC Report
    // Aggregate all QC reports into a single interactive HTML report
    
    // Initialize an empty channel for MultiQC input files
    ch_multiqc_files = Channel.empty()
    
    // Mix in various QC files from different steps
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect())      // FastQC results
    ch_multiqc_files = ch_multiqc_files.mix(BWA_ALIGN.out.stats.collect()) // Alignment metrics
    ch_multiqc_files = ch_multiqc_files.mix(BCFTOOLS_CALL.out.stats.collect()) // Variant calling stats

    // Run MultiQC on all collected QC files
    MULTIQC(
        ch_multiqc_files.collect()
    )
}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/

// This block executes after workflow completion
workflow.onComplete {
    // Send completion email if configured
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log)
    }
    
    // Generate workflow summary
    NfcoreTemplate.summary(workflow, params, log)
    
    // Send notification to messaging service (e.g., Slack) if configured
    if (params.hook_url) {
        NfcoreTemplate.IM_notification(workflow, params, summary_params, projectDir, log)
    }
} 