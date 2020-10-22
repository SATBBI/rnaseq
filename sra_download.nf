////////////////////////////////////////////////////
/* --          VALIDATE INPUTS                 -- */
////////////////////////////////////////////////////

if (params.public_data_ids) { 
    Channel
        .from(file(params.public_data_ids, checkIfExists: true))
        .splitCsv(header:false, sep:'', strip:true)
        .map { it[0] }
        .set { ch_public_data_ids }
} else { 
    exit 1, 'Input file with public database ids not specified!' 
}

////////////////////////////////////////////////////
/* --    IMPORT LOCAL MODULES/SUBWORKFLOWS     -- */
////////////////////////////////////////////////////

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()

include { SRA_IDS_TO_RUNINFO } from './modules/local/process/sra_ids_to_runinfo' addParams( options: [:] )
include { SRA_RUNINFO_TO_FTP } from './modules/local/process/sra_runinfo_to_ftp' addParams( options: [:] )
include { SRA_FASTQ_FTP      } from './modules/local/process/sra_fastq_ftp'      addParams( options: [:] )
include { SRA_FASTQ_DUMP     } from './modules/local/process/sra_fastq_dump'     addParams( options: [:] )

////////////////////////////////////////////////////
/* --           RUN MAIN WORKFLOW              -- */
////////////////////////////////////////////////////

workflow SRA_DOWNLOAD {

    /*
     * MODULE: Get SRA run information for public database ids
     */
    SRA_IDS_TO_RUNINFO (
        ch_public_data_ids
    )

    /*
     * MODULE: Parse SRA run information, create file containing FTP links and read into workflow as [ meta, [reads] ]
     */
    SRA_RUNINFO_TO_FTP (
        SRA_IDS_TO_RUNINFO.out.tsv.collect()
    )

    SRA_RUNINFO_TO_FTP
        .out
        .tsv
        .splitCsv(header:true, sep:',')
        .map { 
            row -> [
                [ id:row.id, single_end:row.single_end.toBoolean(), is_ftp:row.is_ftp.toBoolean(), md5_1:row.md5_1, md5_2:row.md5_2 ],
                [ row.fastq_1, row.fastq_2 ],
            ]
        }
        .set { ch_sra_reads }
    
    /*
     * MODULE: If FTP link is provided in run information then download FastQ directly via FTP and validate with md5sums
     */
    SRA_FASTQ_FTP (
        ch_sra_reads.map { meta, reads -> if (meta.is_ftp)  [ meta, reads ] }
    )

    /*
     * MODULE: If FTP link is NOT provided in run information then download FastQ directly via parallel-fastq-dump
     */
    SRA_FASTQ_DUMP (
        ch_sra_reads.map { meta, reads -> if (!meta.is_ftp) [ meta, reads ] }    
    )
}

////////////////////////////////////////////////////
/* --                  THE END                 -- */
////////////////////////////////////////////////////
