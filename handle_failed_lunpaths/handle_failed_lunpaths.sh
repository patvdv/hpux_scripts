#!/bin/env ksh
#******************************************************************************
# @(#) handle_failed_lunpaths.sh
#******************************************************************************
# @(#) Copyright (C) 2014 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
#
# This program is a free software; you can redistribute it and/or modify
# it under the same terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details
#******************************************************************************
# @(#) MAIN: handle_failed_lunpaths.sh
# DOES: simple script to show and/or remove failed lunpaths (HP-UX 11.31/Agile)
# EXPECTS: (see --help for more options)
# REQUIRES: check_platform(), check_exec_user(), die(), display_usage(), 
#           do_cleanup(), log(), warn()
#           For other pre-requisites see the documentation in display_usage()
#******************************************************************************

#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# define the V.R.F (version/release/fix)
HPUX_VRF="1.0.0"
# UNIX user this script should run as
EXEC_USER="root"
# location of log directory (default)
LOG_DIR="/var/adm"
# location of temporary working storage
TMP_DIR="/var/tmp"
# ------------------------- CONFIGURATION ends here ---------------------------
# miscelleaneous
PATH=${PATH}:/usr/bin:/usr/sbin:/usr/local/bin
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $0)
HOST_NAME=$(hostname)
TMP_FILE="${TMP_DIR}/.${SCRIPT_NAME}.$$"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"  
# command-line parameters
ARG_REMOVE=0            # remove failed lunpath (0=no|1=yes; default: 0)
ARG_DISK=""
ARG_SKIP_CRA=""         # skip_cra option for 'scsimgr disable'
ARG_LOG=1               # logging is on by default
ARG_VERBOSE=1           # STDOUT is on by default

 
#******************************************************************************
# FUNCTION routines
#******************************************************************************

# -----------------------------------------------------------------------------
function check_platform
{
if [[ "$(uname -s)" != "HP-UX" ]]
then
    print -u2 "ERROR: must be run on a HP-UX system"
    exit 1
fi
if [[ "$(uname -r)" != "B.11.31" ]]
then
    print -u2 "ERROR: must be run on version B.11.31"
    exit 1
fi

return 0
}
 
# -----------------------------------------------------------------------------
function check_exec_user
{
(IFS='()'; set -- $(id); print $2) | read UID
if [[ "${UID}" != "${EXEC_USER}" ]]
then
    print -u2 "ERROR: must be run as user '${EXEC_USER}'"
    exit 1
fi

return 0
}

# -----------------------------------------------------------------------------
# log an ERROR: message (via ARG) and exit.
function die
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

# process ARG (if any)
if [[ -n "$1" ]]
then
    if (( ARG_LOG != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'ERROR:'
            LOG_LINE="${LOG_LINE#ERROR: *}"
            print "${NOW}: ERROR: [$$]:" "${LOG_LINE}" >> ${LOG_FILE}
        done
    fi
    print - "$*" | while read LOG_LINE
    do
        # filter leading 'ERROR:'
        LOG_LINE="${LOG_LINE#ERROR: *}"
        print -u2 "ERROR:" "${LOG_LINE}"
    done
fi

# handle alert
(( ARG_SEND_ALERT != 0 )) && print "${LOG_STDIN}" | send_alert "$*"

# finish up work
do_cleanup

exit 1
}

# -----------------------------------------------------------------------------
function display_usage
{
cat << EOT

**** ${SCRIPT_NAME} ****
**** (c) KUDOS BVBA - UNIX (Patrick Van der Veken) ****

Show or removes failed LUNpaths. Only works on HP-UX 11.31 with agile DSFs.

Syntax: ${SCRIPT_DIR}/${SCRIPT_NAME} [--help] | [--version] | [--no-log] ( [--remove] [--skip_cra] ) [--disk=<diskXY> ]


Parameters:

--disk          : operate only on the given disk/lun, otherwise operate on all disks/luns
--no-log        : do not log any messages to the script log file.
--remove        : do the actual removal of the failed paths (default: show only)
--skip-cra      : perform 'scsimgr disable' actions with CRA (Critical Resource Analysis)
--version       : show the script version/release/fix

EOT

return 0
}

# -----------------------------------------------------------------------------
function do_cleanup
{
log "performing cleanup ..."
# remove temporary file(s)
if [[ -f ${TMP_FILE} ]]
then
    rm -f ${TMP_FILE} >/dev/null
    log "${TMP_FILE} temporary file removed"
fi

log "*** finish of ${SCRIPT_NAME} [${CMD_LINE}] ***"

return 0
}

# -----------------------------------------------------------------------------
# log an INFO: message (via ARG).
function log
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

# process ARG (if any)
if [[ -n "$1" ]]
then
    if (( ARG_LOG != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "${NOW}: INFO: [$$]:" "${LOG_LINE}" >> ${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "INFO:" "${LOG_LINE}"
        done
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# log a WARN: message (via ARG).
function warn
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

# process ARG (if any)
if [[ -n "$1" ]]
then
    if (( ARG_LOG != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'WARN:'
            LOG_LINE="${LOG_LINE#WARN: *}"
            print "${NOW}: WARN: [$$]:" "${LOG_LINE}" >>${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'WARN:'
            LOG_LINE="${LOG_LINE#WARN: *}"
            print "WARN:" "${LOG_LINE}"
        done
    fi
fi

return 0
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# parse arguments/parameters
CMD_LINE="$@"
for PARAMETER in ${CMD_LINE}
do
    case ${PARAMETER} in
        -disk*)
            ARG_DISK="${PARAMETER#-disk=}"
            ;;
        --disk*)
            ARG_DISK="${PARAMETER#--disk=}"
            ;;
        -remove|--remove)
            ARG_REMOVE=1
            shift
            ;;
        -skip-cra|--skip-cra)
            ARG_SKIP_CRA=" skip_cra"
            ;;
        -V|-version|--version)
            print "INFO: $0: ${HPUX_VRF}"
            exit 0
            ;;
        \? |-h|-help|--help)
            display_usage
            exit 0
            ;;
    esac   
done

# startup checks
check_platform && check_exec_user

# catch shell signals
trap 'do_cleanup; exit' 1 2 3 15

log "*** start of ${SCRIPT_NAME} [${CMD_LINE}] ***"
(( ARG_LOG != 0 )) && log "logging takes places in ${LOG_FILE}" 

# set disk list
if [[ -z "${ARG_DISK}" ]]
then    
    log "operating on ALL disks/luns"
    ls -1 /dev/rdisk/disk* 2>/dev/null >${TMP_FILE}
else
    ls -1 /dev/rdisk/disk* >/dev/null 2>/dev/null
    if (( $? != 0 ))
    then
        die "disk ${ARG_DISK} does not exist?"
    else
        log "operating on a specific disk/lun: ${ARG_DISK}"
        print "/dev/rdisk/${ARG_DISK}" >${TMP_FILE}
    fi
fi
(( ARG_REMOVE == 0 )) && log "PREVIEW only: showing failed paths without removal"
    
# perform the magic
while read DISK
do
    scsimgr -p lun_map -D ${DISK} 2>/dev/null | grep -i 'failed' 2>/dev/null |\
    while read SCSI_LINE
    do
        log "${SCSI_LINE}"
        HW_PATH=$(print "${SCSI_LINE}" | cut -f3 -d':')
        if (( ARG_REMOVE == 1 )) 
        then
            scsimgr -f disable -H "${HW_PATH}" ${ARG_SKIP_CRA}
            RC=$?
            if (( RC == 0 ))
            then
                log "disabled ${HW_PATH}"
                rmsf -H "${HW_PATH}" 2>/dev/null
                RC=$?
                if (( RC == 0))
                then        
                    log "removed ${HW_PATH}"       
                else
                    warn "failed to remove ${HW_PATH}"      
                fi
            else
                warn "failed to disable ${HW_PATH}"
            fi
        fi
    done
done <${TMP_FILE}

# finish up work
do_cleanup

#******************************************************************************
# END of script
#******************************************************************************