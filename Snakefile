#!/usr/bin/python


'''
This is to run a SnakeMake to add InterVar annotation to a VCF file
'''

import glob
import sys
import os
import pysam
import shutil
from snakemake.utils import R

configfile: "config.yaml"

vcf = config['vcf']
size_file = config['size']
chunk_size = int(config['chunk'])

tabVcf = pysam.TabixFile(vcf)
CHROMOSOMES = tabVcf.contigs
tabVcf.close()

chromEndDict = {}
with open(size_file) as f:
    for line in f:
        line_list = line.split()
        chrom = line_list[0]
        end = int(line_list[1])
        chromEndDict[chrom] = end

CHUNKS = []
for chrom in CHROMOSOMES:
    if not chrom.startswith('chr'):
        chrom = 'chr' + chrom
    if not chromEndDict.get(chrom):
        print('Chromsome ' + chrom + ' not in size file.')
        sys.exit(1)
    chromEnd = chromEndDict[chrom]
    for i in range(0, chromEnd, chunk_size):
        start = str(i)
        end = str(i + chunk_size)
        CHUNKS.append('.'.join([chrom, start, end]))
    




def makeVcfToAvDict(avinput):
    vcfToAvDict = {}
    with open(avinput) as f:
        for line in f:
            line_list = line.split()
            avId = '_'.join(line_list[:5])
            vcfAlt = line_list[9]
            vcfId = line_list[-1]
            if not vcfToAvDict.get(vcfId):
                vcfToAvDict[vcfId] = {}
            vcfToAvDict[vcfId][vcfAlt] = avId
    return vcfToAvDict



include: 'modules/Snakefile_splitVcf'


rule all:
    input:
        'InterVar_bed/build.intervar.bed.gz.tbi'


rule make_avinput:
    input:
        'vcf_chunks/{chunk}.vcf'
    output:
        'avinput/{chunk}.avinput'
    run:
        (chrom, start, end) = wildcards.chunk.split('.')
        shell('perl /usr/local/apps/ANNOVAR/2017-07-16/convert2annovar.pl --format vcf4 --includeinfo {input} --allsample --outfile {input}.avinput')
        sampFiles = glob.glob(input[0] + '.avinput.Samp*.avinput')
        with open(input[0]) as f:
            line = f.readline()
            while line[0] == '#':
                line = f.readline()
        line_list = line.split()
        samples = line_list[9:]
        if len(samples) != len(sampFiles):
            print('Number of samples in ' + input[0] + ' do not match av sample files')
            sys.exit(1)
        lineDict = {}
        for sampFile in sampFiles:
            with open(sampFile) as f:
                for line in f:
                    line_list = line.split()
                    (chrom, start, end, ref, alt) = line_list[:5]
                    pos = int(start)
                    if not lineDict.get(pos):
                        lineDict[pos] = []
                    newLine = '\t'.join(line_list[:-2]) + '\n'
                    lineDict[pos].append(newLine)
        with open(output[0], 'w') as out:
            for pos in sorted(lineDict.keys()):
                lines = set(lineDict[pos])
                for line in lines:
                    out.write(line)

rule run_intervar:
    input:
        'avinput/{chunk}.avinput'
    output:
        'InterVar_chunks/{chunk}.InterVarOutput.hg19_multianno.txt.intervar'
    params:
        'InterVar_chunks/{chunk}.InterVarOutput'
    shell:
        'module load python/2.7;InterVar -i {input} -d $ANNOVAR_DATA/hg19 -o {params}'


rule cat_intervar:
    input:
        expand('InterVar_chunks/{chunk}.InterVarOutput.hg19_multianno.txt.intervar', chunk = CHUNKS)
    output:
        'InterVar_bed/build.intervar.bed'
    run:
        with open(output[0], 'w') as out:
            with open('InterVar_chunks/' + CHUNKS[0] + '.InterVarOutput.hg19_multianno.txt.intervar') as f:
                for line in f:
                    out.write(line)
            for chunk in CHUNKS[1:]:
                with open('InterVar_chunks/' + chunk + '.InterVarOutput.hg19_multianno.txt.intervar') as f:
                    head = f.readline()
                    line = f.readline()
                    while line != '':
                        out.write(line)
                        line = f.readline()

rule bgzip_bed:
    input:
        'InterVar_bed/build.intervar.bed'
    output:
        'InterVar_bed/build.intervar.bed.gz'
    shell:
        'bgzip {input}'


rule tabix_bed:
    input:
        'InterVar_bed/build.intervar.bed.gz'
    output:
        'InterVar_bed/build.intervar.bed.gz.tbi'
    shell:
        'tabix -p bed -S 1 {input}'

