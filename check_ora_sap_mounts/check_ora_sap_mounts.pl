#!/bin/env perl
#******************************************************************************
# @(#) check_ora_sap_mounts.pl
#******************************************************************************
# @(#) Copyright (C) 2012 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
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
# @(#) MAIN: check_ora_sap_mounts.pl
# DOES: evaluates the mount options of the Oracle filesystems on remote systems
#       to those of a defined standard for HP-UX systems
# EXPECTS: N/A
# REQUIRES: N/A
#******************************************************************************

#******************************************************************************
# PRAGMA's & LIBRARIES
#******************************************************************************

use strict;
use warnings;


#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# path to file containing list of database hosts to check
my $hosts_list = '/root/myhosts.list';
# common parent directory for SAP filesystems
my $parent_dir = '/oracle';
# path to output report file
my $output_file = "/var/log/$0.lst";
# oracle mount point standards
my %standard_opts = (
    'ora_redo' => ['delaylog', 'nodatainlog', 'convosync=direct', 'mincache=direct', 'largefiles'],
    'sap_redo' => ['delaylog', 'nodatainlog', 'largefiles'],
    'ora_arch' => ['delaylog', 'nodatainlog', 'convosync=direct', 'mincache=direct', 'largefiles'],
    'ora_data' => ['delaylog', 'nodatainlog', 'convosync=direct', 'mincache=direct', 'largefiles'],
    'ora_prog' => ['delaylog', 'nodatainlog', 'largefiles'],
    'ora_fra'  => ['delaylog', 'nodatainlog', 'convosync=direct', 'mincache=direct', 'largefiles'],
    'ora_ulog' => ['delaylog', 'nodatainlog', 'largefiles']
);
# ------------------------- CONFIGURATION ends here ---------------------------
my %ora_mounts = ();
my (@server_data, @mount_bits) = ();
my ($remote_command, $server, $server_data);


#******************************************************************************
# MAIN routine
#******************************************************************************

# -----------------------------------------------------------------------------
# Get oracle mount point info on each server 
# -----------------------------------------------------------------------------

print "INFO: fetching mount info from remove servers ...\n";
open (SRV_LIST, $hosts_file) or die ("ERROR: opening file: $!");
while (<SRV_LIST>) {
    $server = $_;
    $server =~ s/\n//g;
    $remote_command = "/usr/sbin/mount | /usr/bin/grep -E -e '^".${parent_dir}."'";
    print "INFO: polling $server ...\n";
    @server_data = `ssh -q -o ConnectTimeout=10 $server $remote_command`;
    if (@server_data) {
        foreach $server_data (@server_data) {
            my $fs;
            chomp ($server_data);
            # take out the irrelevant bits (fields 0,2,3 kept)
            @mount_bits = split (/\s/, $server_data);
            $fs = $mount_bits[0];
            $ora_mounts{$server}{$fs} = $mount_bits[3];
        }
    } else {
        print "ERROR: no output returned from $server!\n"
    }
}
close (SRV_LIST);

# -----------------------------------------------------------------------------
# Process collected mount info (serialized)
# ----------------------------------------------------------------------------- 

print "INFO: checking mount options for all Oracle FS (see: $output_file) ...\n";
open (ORA_MOUNTS, ">$output_file") or die ("ERROR: opening file: $!");
foreach my $server (sort keys %ora_mounts) {
    foreach my $fs (sort keys %{$ora_mounts{$server}}) {
        my ($fs_type, $all_opts);
        my (@mount_opts, @all_opts, @only_in_standard, @only_in_mount);
        my $only_in_standard = ''; my $only_in_mount = '';
        my (%only_standard_tmp, %only_mount_tmp);

        # which kind of FS is it?
        if ($fs =~ m#${parent_dir}/.*/[0-9]+#) {
            $fs_type = 'ora_prog';
        } elsif ($fs =~ m#${parent_dir}/.*/(ora|sap)arch# || $fs =~ m#${parent_dir}/.*/buffer#
            || $fs =~ m#${parent_dir}/(ora|sap)arch/.*#) {
                $fs_type = 'ora_arch';
        } elsif ($fs =~ m#${parent_dir}/(.*)/origlogA# || $fs =~ m#${parent_dir}/(.*)/origlogB#
            || $fs =~ m#${parent_dir}/(.*)/mirrlogA# || $fs =~ m#${parent_dir}/(.*)/mirrlogB#
            || $fs =~ m#${parent_dir}/oraredo/(.*)#) {
                # SAP or Oracle instance?
                if (defined ($1)) {
                    if (length ($1) == 3) {
                        $fs_type = 'sap_redo';
                    } else {
                        $fs_type = 'ora_redo';
                    }
                } else {
                    $fs_type = 'ora_redo';
                }
        } elsif ($fs =~ m#${parent_dir}/.*data.*#) {
            $fs_type = 'ora_data';
        } elsif ($fs =~ m#${parent_dir}/.*/orafra# || $fs =~ m#${parent_dir}/orafra/.*#) {
            $fs_type = 'ora_fra';

        } else {
            $fs_type = 'unknown';
        }

        # check against standard
        if ($fs_type eq 'unknown') {
            print ORA_MOUNTS "$server:$fs:$fs_type:NOT_CHECKED:$ora_mounts{$server}{$fs}\n";
        } else {
            @all_opts = split (/,/, $ora_mounts{$server}{$fs});
            # discard irrelevant opts for comparison
            foreach $all_opts (@all_opts) {
                unless ($all_opts =~ /ioerror=.*/ || $all_opts =~ /dev=.*/) {
                    push (@mount_opts, $all_opts);    
                }
            }
            %only_standard_tmp = map {$_=>1} @mount_opts;
            @only_in_standard = grep { !$only_standard_tmp{$_} } @{$standard_opts{$fs_type}}; 
            if (@only_in_standard) {
                foreach my $entry (@only_in_standard) { $only_in_standard .= $entry."(-)," };
            }
            chop ($only_in_standard) if ($only_in_standard);

            %only_mount_tmp = map {$_=>1} @{$standard_opts{$fs_type}};
            @only_in_mount = grep { !$only_mount_tmp{$_} } @mount_opts;
            if (@only_in_mount) {
                foreach my $entry (@only_in_mount) { $only_in_mount .= $entry."(+)," };
            }
            chop ($only_in_mount) if ($only_in_mount);

            if (@only_in_standard || @only_in_mount) {
                print ORA_MOUNTS "$server:$fs:$fs_type:NOK:$only_in_standard:$only_in_mount\n";
            } else {
                print ORA_MOUNTS "$server:$fs:$fs_type:OK\n";
            }
        }
    }
}
close (ORA_MOUNTS);

exit (0);

#******************************************************************************
# END of script
#******************************************************************************