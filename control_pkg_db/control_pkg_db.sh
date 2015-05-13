#!/bin/env ksh
#******************************************************************************
# @(#) control_pkg_db.sh
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
# @(#) MAIN: control_pkg_db.sh
# DOES: (de-)activate database diskgroup(s) and mounts their filesystem(s).
# EXPECTS: (see --help for more options)
# REQUIRES: check_config_file(), check_environment(), check_params(), 
#           check_sg_pkg(), deport_vxvm_dg(), die(), display_usage(), do_cleanup(),
#           get_sg_pkg_config(), check_sg_status(), get_vxfs_fs_names(), 
#           get_vxvm_dg_names(), import_vxvm_dg(), is_vxfs_fs_mounted(), 
#           is_vxvm_dg_imported(), is_vxvm_dg_used(), log(), logc(), 
#           mount_vxfs_fs(), umount_vxfs_fs(), warn()
#           For other pre-requisites see the documentation in display_usage()
#******************************************************************************

#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# define the V.R.F (version/release/fix)
HPUX_VRF="1.0.0"
# account that is allowed to execute the script
EXEC_USER="root"
# umount counter (how often to try to un-mount?)
UMOUNT_COUNT=3
# location of log directory (default), (see --log-dir)
LOG_DIR="/var/log"
# location of temporary working storage
TMP_DIR="/var/tmp"
# ------------------------- CONFIGURATION ends here ---------------------------
# miscellaneous
PATH=${PATH}:/usr/bin:/usr/sbin:/usr/local/bin
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $0)
HOST_NAME=$(hostname)
TMP_PKG_FILE="${TMP_DIR}/.${SCRIPT_NAME}.pkg.$$"
TMP_RC_FILE="${TMP_DIR}/.${SCRIPT_NAME}.rc.$$"
# command-line parameters
ARG_ACTION=0            # default is nothing
ARG_USE_CLUSTER=1       # default is to get configuration from cluster
ARG_LOG_DIR=""          # location of the log directory
ARG_LOG=1               # logging is on by default
ARG_VERBOSE=0           # STDOUT is off by default


#******************************************************************************
# FUNCTION routines
#******************************************************************************

# -----------------------------------------------------------------------------
# do same basic checks on a given configuration file with DG/FS data
function check_config_file
{
# file should have 5 fields
HAS_BAD_FIELDS=$(awk 'BEGIN { FS=":" } { print NF }' < ${ARG_USE_FILE} | grep -c -v '5' 2>/dev/null)
(( HAS_BAD_FIELDS > 0 )) &&
    die "configuration file ${ARG_USE_FILE} is missing some field(s) (should be 4)"
    
# 3rd field should be a VXVM volume device string
HAS_BAD_VXVM=$(cut -f3 -d':' <${ARG_USE_FILE} | grep -c -v -E -e '^\/dev\/vx\/dsk')
(( HAS_BAD_VXVM > 0 )) &&
    die "configuration file ${ARG_USE_FILE} has bad VXVM device name(s) in the 2nd field"    
    
# 4th field should be a VXFS file system string
HAS_BAD_VXFS=$(cut -f4 -d':' <${ARG_USE_FILE} | grep -c -v -E -e '^\/')
(( HAS_BAD_VXFS > 0 )) &&
    die "configuration file ${ARG_USE_FILE} has bad VXFS name(s) in the 3rd field"   

return 0
}   
        
# -----------------------------------------------------------------------------
# perform some checks on the running environment/system
function check_environment
{
# check platform
if [[ "$(uname -s)" != "HP-UX" ]]
then
    print -u2 "ERROR: must be run on an HP-UX system"
    exit 1
fi
# check run user
(IFS='()'; set -- $(id); print $2) | read UID
if [[ "${UID}" != "${EXEC_USER}" ]]
then
    print -u2 "ERROR: must be run as user '${EXEC_USER}'. Think 'sudo' :-)"
    exit 1
fi
# check for presence of serviceguard
SG_DAEMON="/usr/lbin/cmcld"
if [[ ! -f ${SG_DAEMON} ]]
then
    print -u2 "ERROR: missing ${SG_DAEMON}, this is not a Serviceguard cluster?"
    exit 1
fi

return 0
}

# -----------------------------------------------------------------------------
function check_params
{
# -- ALL
if (( ARG_ACTION < 1 || ARG_ACTION > 4 ))
then
    display_usage
    exit 0
fi
# --get
if (( ARG_ACTION == 1))
then
    # showing configuration data is interactive only
    ARG_LOG=0
    ARG_VERBOSE=0
    if [[ -n ${ARG_USE_FILE} ]]
    then
        print -u2 "ERROR: you cannot use the '-get' option in combination with '-use-file'"
        exit 1      
    fi
fi
# --status
if (( ARG_ACTION == 3))
then
    # status report is interactive only
    ARG_LOG=0
    ARG_VERBOSE=0
fi
# --get/--mount/--status/--umount
if (( ARG_ACTION >= 1 && ARG_ACTION < 4 ))
then
    if [[ -n "${ARG_PKG}" && -n "${ARG_USE_FILE}" ]]
    then
        print -u2 "ERROR: either use a package (--pkg) or configuration file (--use-file)"
        exit 1  
    fi
    if (( ${ARG_USE_CLUSTER} != 0 ))
    then
        if [[ -z "${ARG_PKG}" ]] 
        then
            print -u2 "ERROR: no database/package specified. Missing parameter for '--pkg'"
            exit 1
        fi
    else
        if [[ ! -f "${ARG_USE_FILE}" ]] 
        then
            print -u2 "ERROR: cannot find the specified configuration file at '${ARG_USE_FILE}'"
            exit 1
        fi
    fi
fi
# --log-dir
[[ -z "${ARG_LOG_DIR}" ]] || LOG_DIR="${ARG_LOG_DIR}"
if (( ARG_LOG != 0 ))
then
    if [ \( ! -d "${LOG_DIR}" \) -o \( ! -w "${LOG_DIR}" \) ]
    then
        # switch off logging intelligently when needed for permission problems 
        # since this script may run with root/non-root actions
        print -u2 "WARN: unable to write to the log directory at ${LOG_DIR}, disabling logging"
        ARG_LOG=0 
    else
        LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"    
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# check serviceguard package properties
function check_sg_pkg
{
PKG="$1"

# does the package exist?
cmviewcl -f line -p ${PKG} >/dev/null 2>/dev/null || return 1

# check some of the package properties
cmviewcl -f line -p ${PKG} 2>/dev/null | while read SG_LINE
do
    case "${SG_LINE}" in
        *type=multi_node*)
            return 2
            ;;
    esac
done

return 0
}

# -----------------------------------------------------------------------------
# deport a vxvm diskgroup
function deport_vxvm_dg
{
DG="$1"

vxdg deport ${DG} || return 1

is_vxvm_dg_imported ${DG}
if (( $? > 0 ))
then
    return 1
else
    return 0
fi
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

(De-)activate database diskgroup(s) (DG) & their filesystem(s) (FS) -- Only works with VXVM!

Syntax: ${SCRIPT_NAME} [--help] | [--version] | [--verbose] [--no-log] [--log-dir=<log_directory>]
                (--status | --get | --mount | --umount) --pkg=<db_package> | --use-file=<config_file> 


Parameters:

--get           : display the configuration info from the running cluster for the 
                  database DGs & FSs in order to create a custom configuration file
--help          : show this help text
--log-dir       : specify a log directory location.
--mount         : activate the database DGs & FSs
--no-log        : do not log any messages to the script log file.
--pkg|--package : name of the serviguard database package
--status        : show the current status of the database DGs & FSs
--umount        : de-activate the database DGs & FSs
--use-file      : use the supplied configuration file with list of DGs & FSs 
                  (instead of querying the cluster configuration)
--verbose       : execute actions with full feedback/output
--version       : show the script version/release/fix

Note 1: this script should never be run on a RAC cluster or single node instance

Note 2: never forget to un-mount your database DG/FS before starting the cluster
        package! To be sure run the script with '--status' on BOTH cluster nodes.

Examples (using package 'dbacme', database 'acme'):

1) Import DG and mount FS of the dbacme database (using the cluster configuration)
    ${SCRIPT_NAME} --mount --pkg=dbacme
        
2) Get current status of DG & FS (using the cluster configuration)
    ${SCRIPT_NAME} --status --pkg=dbacme

3) Unmount FS & deport DG of the dbacme database (using a custom config)
    ${SCRIPT_NAME} --umount --use-file=dbacme.conf
        
4) Get the configuration data from the cluster to create a custom config file:
    ${SCRIPT_NAME} --get --pkg=dbacme >dbacme.conf

EOT

return 0
}

# -----------------------------------------------------------------------------
function do_cleanup
{
log "performing cleanup ..."
# remove temporary file(s)
if [[ -f ${TMP_PKG_FILE} ]]
then
    rm -f ${TMP_PKG_FILE} >/dev/null
    log "${TMP_PKG_FILE} temporary file removed"
fi
if [[ -f ${TMP_RC_FILE} ]]
then
    rm -f ${TMP_RC_FILE} >/dev/null
    log "${TMP_RC_FILE} temporary file removed"
fi

log "*** finish of ${SCRIPT_NAME} [${CMD_LINE}] ***"

return 0
}

# -----------------------------------------------------------------------------
# get serviceguard package configuration
function get_sg_pkg_config
{
(cmviewcl -v -f line -p ${ARG_PKG} >${TMP_PKG_FILE} 2>/dev/null; print $? > ${TMP_RC_FILE}; exit) 2>&1 | logc

# fetch return code from subshell
RC=$(< ${TMP_RC_FILE})
(( RC != 0 )) && return 1

# simple check on the cluster configuration file
[[ -s ${TMP_PKG_FILE} ]] || return 1

return 0
}

# -----------------------------------------------------------------------------
# get run-(status) of serviceguard package
function get_sg_pkg_status
{
PKG="$1"

# check some of the package properties
cmviewcl -f line -p ${PKG} 2>/dev/null | while read SG_LINE
do
    case "${SG_LINE}" in
        *status=up)
            print "UP"
            ;;
        *status=down)
            print "DOWN"
            ;;
        *status=starting)
            print "STARTING"
            ;;
        *status=halting)
            print "HALTING"
            ;;
    esac
done

return 0
}

# -----------------------------------------------------------------------------
# get VXFS fs names (& VXVM volumes) for a specific diskgroup
function get_vxfs_fs_names
{
DG="$1"
 
if (( ARG_USE_CLUSTER != 0 )) 
then
    # get config from the cluster configuration file
    # sample entries for a filesystem:
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|filesystem=/dev/vx/dsk/dbacmeredoadg/redo1_vol
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_name=/dev/vx/dsk/dbacmeredoadg/redo1_vol
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_server=""
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_directory=/oradbs/redoa1/DB_ACME
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_type="vxfs"
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_mount_opt="-o rw,largefiles,nodatainlog,mincache=direct,convosync=direct"
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_umount_opt=""
    # filesystem:/dev/vx/dsk/dbacmeredoadg/redo1_vol|fs_fsck_opt=""
    grep -E -e "^filesystem:.*\/${DG}\/.*(fs_directory|fs_mount_opt)=.*" ${TMP_PKG_FILE} 2>/dev/null |\
    while read LINE
    do
        case "${LINE}" in 
            *fs_directory*)
                FS=$(print "${LINE}" | cut -f2 -d'=')
                VOL=$(print "${LINE}" | cut -f1 -d'|' | cut -f2 -d':')
                ;;
            *fs_mount_opt*)
                OPTS=$(print "${LINE}" | cut -f2 -d'|' | cut -f2- -d'=' | tr -d '\"')
                ;;
        esac
        if [[ -n ${VOL} && -n ${FS} && -n ${OPTS} ]]
        then
            print "${VOL}:${FS}:${OPTS}"
            VOL=""; FS=""; OPTS=""
        fi
    done
else
    # get config from the customer configuration file
    # sample entries for a filesystem:
    # dbacme:dbacmedbf01dg:/dev/vx/dsk/dbacmedbf01dg/oradbs_acme_dbf01_vol:/oradbs/acme/dbf01:-o rw,largefiles,nodatainlog,mincache
    # dbacme:dbacmefradg:/dev/vx/dsk/dbacmefradg/oradbs_acme_fra_vol:/oradbs/acme/fra:-o rw,largefiles,nodatainlog,mincache
    # dbacme:dbacmeredoadg:/dev/vx/dsk/dbacmeredoadg/redo1_vol:/oradbs/redoa1/DB_acme:-o rw,largefiles,nodatainlog,mincache
    # dbacme:dbacmeredobdg:/dev/vx/dsk/dbacmeredobdg/redo1_vol:/oradbs/redob1/DB_acme:-o rw,largefiles,nodatainlog,mincache
    grep -E -e ":${DG}:" ${ARG_USE_FILE} 2>/dev/null | cut -f3-5 -d':' 2>/dev/null
fi

return 0
}

# -----------------------------------------------------------------------------
# get VXVM diskgroup names
function get_vxvm_dg_names
{
if (( ARG_USE_CLUSTER != 0 )) 
then
    # get config from the cluster configuration file
    # sample entries for a diskgroup:
    # vxvm_dg:dbacmedbf01dg|vxvm_dg=dbacmedbf01dg
    grep -E -e '^vxvm_dg:' ${TMP_PKG_FILE} 2>/dev/null | cut -f2 -d'='
else
    # get config from the customer configuration file
    # sample entries for a diskgroup:
    # dbacmedbf01dg:/dev/vx/dsk/dbacmedbf01dg/oradbs_acme_dbf01_vol:/oradbs/acme/dbf01:-o rw,largefiles,nodatainlog,mincache
    # dbacmefradg:/dev/vx/dsk/dbacmefradg/oradbs_acme_fra_vol:/oradbs/acme/fra:-o rw,largefiles,nodatainlog,mincache
    # dbacmeredoadg:/dev/vx/dsk/dbacmeredoadg/redo1_vol:/oradbs/redoa1/DB_acme:-o rw,largefiles,nodatainlog,mincache
    # dbacmeredobdg:/dev/vx/dsk/dbacmeredobdg/redo1_vol:/oradbs/redob1/DB_acme:-o rw,largefiles,nodatainlog,mincache
    cut -f2 -d':' < ${ARG_USE_FILE} 2>/dev/null 
fi

return 0
}

# -----------------------------------------------------------------------------
# import a vxvm diskgroup
function import_vxvm_dg
{
DG="$1"

vxdg import ${DG} || return 1

is_vxvm_dg_imported ${DG}
if (( $? > 0 ))
then
    return 0
else
    return 1
fi
}

# -----------------------------------------------------------------------------
# check if given VXFS filesystem is mounted/used
function is_vxfs_fs_mounted
{
CHECK_FS=$1

MOUNTED_FS=$(mount | grep -c -E -e "^${CHECK_FS}[[:space:]]+")

return ${MOUNTED_FS}
}

# -----------------------------------------------------------------------------
# check if given VXVM diskgroup is imported
function is_vxvm_dg_imported
{
CHECK_DG=$1

IMPORTED_DG=$(vxdg list | grep -c -E -e "^${VXVM_DG}")

return ${IMPORTED_DG}
}

# -----------------------------------------------------------------------------
# check if given VXVM diskgroup is in use (i.e. by mounted filesystems)
function is_vxvm_dg_used
{
CHECK_DG=$1

USED_DG=$(mount | grep -c -E -e "\/${CHECK_DG}\/")

return ${USED_DG}
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
# log an INFO: message (via STDIN). Do not use when STDIN is still open
function logc
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"
LOG_STDIN=""

# process STDIN (if any)
[[ ! -t 0 ]] && LOG_STDIN="$(cat)"
if [[ -n "${LOG_STDIN}" ]]
then
    if (( ARG_LOG != 0 ))
    then
        print - "${LOG_STDIN}" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "${NOW}: INFO: [$$]:" "${LOG_LINE}" >> ${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE != 0 ))
    then
        print - "${LOG_STDIN}" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "INFO:" "${LOG_LINE}"
        done
    fi
fi

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
# mount an VXFS filesystem
function mount_vxfs_fs
{
FS="$1"
VOL="$2"
OPTS="$3"

# mount filesystem
(mount -F vxfs ${OPTS} ${VOL} ${FS}; print $? > ${TMP_RC_FILE}; exit ) 2>&1 | logc

# fetch return code from subshell
RC=$(< ${TMP_RC_FILE})
(( RC != 0 )) && return 1

is_vxfs_fs_mounted ${FS}
if (( $? > 0 ))
then
    return 0
else
    return 1
fi
}

# -----------------------------------------------------------------------------
# un-mount an VXFS filesystem
function umount_vxfs_fs
{
FS="$1"

(umount -v ${FS}; print $? > ${TMP_RC_FILE}; exit) 2>&1 | logc

# fetch return code from subshell
RC=$(< ${TMP_RC_FILE})
(( RC != 0 )) && return 1

is_vxfs_fs_mounted ${FS}

if (( $? > 0 ))
then
    return 1
else
    return 0
fi
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
    print - "$*" | while read LOG_LINE
    do
        # filter leading 'WARN:'
        LOG_LINE="${LOG_LINE#WARN: *}"
        print "WARN:" "${LOG_LINE}"
    done
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
        -log-dir=*)
            ARG_LOG_DIR="${PARAMETER#-log-dir=}"
            ;;
        --log-dir=*)
            ARG_LOG_DIR="${PARAMETER#--log-dir=}"
            ;;
        -g|-get|--get)
            ARG_ACTION=1
            ;;
        -m|-mount|--mount)
            ARG_ACTION=2
            ;;
        -no-log|--no-log)
            ARG_LOG=0
            ;;
        -package*)
            ARG_PKG="${PARAMETER#-package=}"
            ;;
        --package*)
            ARG_PKG="${PARAMETER#--package=}"
            ;;
        -pkg*)
            ARG_PKG="${PARAMETER#-pkg=}"
            ;;
        --pkg*)
            ARG_PKG="${PARAMETER#--pkg=}"
            ;;  
        -s|-status|--status)
            ARG_ACTION=3
            ;;
        -u|-umount|--umount)
            ARG_ACTION=4
            ;;
        -use-file=*)
            ARG_USE_FILE="${PARAMETER#-use-file=}"
            ARG_USE_CLUSTER=0
            ;;
        --use-file=*)
            ARG_USE_FILE="${PARAMETER#--use-file=}"
            ARG_USE_CLUSTER=0
            ;;
        -v|-verbose|--verbose)
            ARG_VERBOSE=1
            ;;
        -V|-version|--version)
            print "INFO: $0: ${HPUX_VRF}"
            exit 0
            ;;
        \?|-h|-help|--help)
            display_usage
            exit 0
            ;;
    esac    
done

# startup checks
check_params && check_environment

# catch shell signals
trap 'do_cleanup; exit' 1 2 3 15

log "*** start of ${SCRIPT_NAME} [${CMD_LINE}] ***"    
(( ARG_LOG != 0 )) && log "logging takes places in ${LOG_FILE}"  

# do checks on the configuration file or the serviceguard package properties
if (( ARG_USE_CLUSTER != 0 ))
then
    # check that package exists and is of the right type
    check_sg_pkg ${ARG_PKG} 'config' 2>/dev/null
    case $? in
        0)  # pass
            :
            ;;
        1)  # no package
            die "package ${ARG_PKG} does not exist"
            ;;
        2)  # no failover package
            die "package ${ARG_PKG} is multi-node/RAC, will not continue"
    esac
else
    check_config_file || die "problem in the supplied configuration file, will not continue"
fi
    
# main action part of the script
case ${ARG_ACTION} in
    1)  # get details to build a configuration file
        log "compiling data for configuration file ..."
        if (( ARG_USE_CLUSTER != 0 ))
        then
            get_sg_pkg_config || \
                die "could not get serviceguard configuration for package ${ARG_PKG}"
        fi
        get_vxvm_dg_names | while read VXVM_DG
        do
            get_vxfs_fs_names ${VXVM_DG} | while read FS_LINE
            do
                VXFS_VOL=$(print "${FS_LINE}" | cut -f1 -d ':')
                VXFS_FS=$(print "${FS_LINE}" | cut -f2 -d ':')
                VXFS_OPTS=$(print "${FS_LINE}" | cut -f3 -d ':')
                printf "%s:%s:%s:%s:%s\n" ${ARG_PKG} ${VXVM_DG} ${VXFS_VOL} \
                                                ${VXFS_FS} "${VXFS_OPTS}"
            done
        done
        ;;   
    2)  # import DG(s) + mount FS
        if (( ARG_USE_CLUSTER != 0 ))
        then
            get_sg_pkg_config || \
                die "could not get serviceguard configuration for package ${ARG_PKG}"
        else
            # get package name from config file
            ARG_PKG=$(tail -n 1 ${ARG_USE_FILE} | cut -f1 -d':')
        fi
        PKG_STATUS=$(get_sg_pkg_status "${ARG_PKG}")
        case "${PKG_STATUS}" in
            UP|STARTING|HALTING)
                die "package ${ARG_PKG} is active/starting/halting, will not continue"
                ;;
            DOWN|down)
                : # pass
                ;;
            *)
                die "package ${ARG_PKG} has unknown status. Please check!"
                ;;
        esac
        log "activating ${ARG_PKG} ..."
        get_vxvm_dg_names | while read VXVM_DG
        do
            # import DG
            log "checking DG ${VXVM_DG} ..."
            is_vxvm_dg_imported ${VXVM_DG}
            if (( $? == 0 ))
            then
                log "importing DG ${VXVM_DG}"
                import_vxvm_dg ${VXVM_DG}
                if (( $? == 0 ))
                then
                    log "successfully imported DG ${VXVM_DG}"                             
                else
                    warn "could not import DG ${VXVM_DG}. Skipping!"
                fi  
            else 
                log "DG ${VXVM_DG} is already imported"
            fi
            # mount FS
            is_vxvm_dg_imported ${VXVM_DG}
            if (( $? != 0 ))
            then
                get_vxfs_fs_names ${VXVM_DG} | while read FS_LINE
                do
                    COUNT=0
                    VXFS_VOL=$(print "${FS_LINE}" | cut -f1 -d ':')
                    VXFS_FS=$(print "${FS_LINE}" | cut -f2 -d ':')
                    VXFS_OPTS=$(print "${FS_LINE}" | cut -f3 -d ':')
                    is_vxfs_fs_mounted ${VXFS_FS}
                    if (( $? == 0 )) 
                    then
                        # mount here
                        log "mounting FS ${VXFS_FS}"
                        mount_vxfs_fs ${VXFS_FS} ${VXFS_VOL} "${VXFS_OPTS}"
                        if (( $? == 0 ))
                        then
                            log "successfully mounted FS ${VXFS_FS} on ${VXFS_VOL}"                         
                        else
                            warn "unable to mount FS ${VXFS_FS} on ${VXFS_VOL}. Skipping!"
                        fi
                    else
                        log "FS ${VXFS_FS} is already mounted"
                    fi
                done
            fi
        done
        ;;
    3)  # status of DG(s) + FS  
        if (( ARG_USE_CLUSTER != 0 ))
        then
            get_sg_pkg_config || \
                die "could not get serviceguard configuration for package ${ARG_PKG}"
        else
            # get package name from config file
            ARG_PKG=$(tail -n 1 ${ARG_USE_FILE} | cut -f1 -d':')
        fi
        PKG_STATUS=$(get_sg_pkg_status "${ARG_PKG}")
        case "${PKG_STATUS}" in
            UP|STARTING|HALTING)
                : # pass
                ;;
            DOWN|down)
                : # pass
                ;;
            *)
                die "package ${ARG_PKG} has unknown status. Please check!"
                ;;
        esac
        log "checking status of diskgroup(s)/filesystem(s)"
        printf "\nPKG %-32s : %s\n" ${ARG_PKG} ${PKG_STATUS}
        get_vxvm_dg_names | while read VXVM_DG
        do
            printf "\nDG %-33s : " ${VXVM_DG}
            is_vxvm_dg_imported ${VXVM_DG}
            if (( $? == 0 ))
            then
                print "DEPORTED"
            else
                print "IMPORTED"
            fi
            get_vxfs_fs_names ${VXVM_DG} | while read FS_LINE
            do
                VXFS_FS=$(print "${FS_LINE}" | cut -f2 -d ':')
                VXFS_OPTS=$(print "${FS_LINE}" | cut -f3 -d ':')
                printf "    FS %-29s : " ${VXFS_FS}
                is_vxfs_fs_mounted ${VXFS_FS}
                if (( $? == 0 ))
                then
                    print "UNMOUNTED"
                else
                    print "MOUNTED [${VXFS_OPTS}]"
                fi
            done
        done
        print
        ;;          
    4)  # deport DG(s) + umount FS
        if (( ARG_USE_CLUSTER != 0 ))
        then
            get_sg_pkg_config || \
                die "could not get serviceguard configuration for package ${ARG_PKG}"
        else
            # get package name from config file
            ARG_PKG=$(tail -n 1 ${ARG_USE_FILE} | cut -f1 -d':')
        fi
        PKG_STATUS=$(get_sg_pkg_status "${ARG_PKG}")
        case "${PKG_STATUS}" in
            UP|STARTING|HALTING)
                die "package ${ARG_PKG} is active/starting/halting, will not continue"
                ;;
            DOWN|down)
                : # pass
                ;;
            *)
                die "package ${ARG_PKG} has unknown status. Please check!"
                ;;
        esac
        log "de-activating ${ARG_PKG} ..."
        get_vxvm_dg_names | while read VXVM_DG
        do
            log "checking DG ${VXVM_DG} ..."
            is_vxvm_dg_imported ${VXVM_DG}
            if (( $? == 0 ))
            then
                log "DG ${VXVM_DG} is already deported"
            else
                # umount FS
                get_vxfs_fs_names ${VXVM_DG} | while read FS_LINE
                do
                    COUNT=0
                    VXFS_FS=$(print "${FS_LINE}" | cut -f2 -d ':')
                    is_vxfs_fs_mounted ${VXFS_FS}
                    if (( $? == 0 ))
                    then
                        log "FS ${VXFS_FS} is already un-mounted"
                    else
                        log "un-mounting FS ${VXFS_FS} (max ${UMOUNT_COUNT} tries)"
                        # umount here
                        while (( COUNT < UMOUNT_COUNT ))
                        do
                            umount_vxfs_fs ${VXFS_FS}
                            if (( $? == 0 ))
                            then
                                log "successfully un-mounted FS ${VXFS_FS}" 
                                break 1
                            else
                                warn "unable to un-mount FS ${VXFS_FS}. Trying again"
                            fi
                            COUNT=$(( COUNT + 1 ))
                        done
                        # check is it still mounted?
                        is_vxfs_fs_mounted ${VXFS_FS}
                        (( $? == 0 )) || \
                            warn "failed to un-mount FS ${VXFS_FS}. Giving up!"
                    fi
                done
                # deport DG
                is_vxvm_dg_used ${VXVM_DG}
                MOUNT_RC=$?
                if (( MOUNT_RC != 0 ))
                then
                    warn "found ${MOUNT_RC} (still) mounted FS on ${VXVM_DG}. Will not deport ${VXVM_DG}!" 
                else
                    deport_vxvm_dg ${VXVM_DG}
                    if (( $? == 0 ))
                    then
                        log "successfully deported DG ${VXVM_DG}"               
                    else
                        warn "could not deport DG ${VXVM_DG}. Check manually!"
                    fi
                fi
            fi
        done
        ;;
esac
    
# finish up work
do_cleanup

#******************************************************************************
# END of script
#******************************************************************************
