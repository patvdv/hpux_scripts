#!/usr/bin/env perl
#******************************************************************************
# @(#) lvs.pl
#******************************************************************************
# @(#) Copyright (C) 2016 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
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
# This script will display HP-UX LVM information in Linux style
# 
# Based on https://jreypo.wordpress.com/2010/02/16/linux-lvm-commands-in-hp-ux/
#
# @(#) HISTORY: see perldoc 'lvs.pl'
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# PRAGMA's & LIBRARIES
#******************************************************************************

use strict;
use warnings;
use POSIX qw(uname);
use Getopt::Long;
use Pod::Usage;
$|++;


#******************************************************************************
# DATA structures
#******************************************************************************

my ($os, $version, $footer);
my %options;
my (@vgdisplay, @lvdisplay);


#******************************************************************************
# MAIN routine
#******************************************************************************

# where and what am I?
die ("ERROR: must be invoked as root\n") if ($<);
($os, $version) = (uname())[0,2];
die ("ERROR: only runs on HP-UX v11.31") unless ($os eq 'HP-UX' and $version eq 'B.11.31');

# process command-line options
if ( @ARGV > 0 ) {
    Getopt::Long::Configure('prefix_pattern=(--|-|\/)', 'bundling', 'no_ignore_case');
    GetOptions( \%options,
            qw(
                help|h|?
                size|s=s
                vg|g=s
            ));
}
# check options
if ($options{'help'}) {
    pod2usage(-verbose => 3);
    exit (0);
};
unless ($options{'size'}) {
    $options{'size'} = 'GB';
};

# print header
printf STDOUT ("\n%-30s %-12s %-17s %-6s %-10s %-7s %-8s %-8s\n", 
        "LV", "VG", "Status", "Size", "Permissions", "Mirrors", "Stripes", "Allocation");

# fetch LVOLs
if ($options{'vg'}) {
    @vgdisplay = `/usr/sbin/vgdisplay -vF ${options{'vg'}} | grep "^lv_name"`;
} else {
    @vgdisplay = `/usr/sbin/vgdisplay -vF | grep "^lv_name"`;
}
die "failed to execute: $!" if ($?);

# loop over LVOLs
foreach my $lvol (@vgdisplay) {
        
    my $lv_name = (split (/=/, (split (/:/, $lvol))[0]))[1];

    @lvdisplay = `/usr/sbin/lvdisplay -F ${lv_name}`;
    die "failed to execute: $!" if ($?);
    
    # loop over lvdisplay
    foreach my $lv_entry (@lvdisplay) {
        
        my ($vg_name, $lv_status, $lv_perm, $lv_alloc) = ("","","","");
        my ($lv_mirrors, $lv_stripes, $lv_size) = (0,0,0);
        
        my @lv_data = split (/:/, $lv_entry);

        # loop over LVOL data
        foreach my $lv_field (@lv_data) {

            $vg_name    = $1 if ($lv_field =~ m%^lv_name=/dev/(.*)/%);
            $lv_status  = $1 if ($lv_field =~ m%^lv_status=(.*)%);
            $lv_perm    = $1 if ($lv_field =~ m%^lv_permission=(.*)%);
            $lv_mirrors = $1 if ($lv_field =~ m%^mirror_copies=(.*)%);
            $lv_stripes = $1 if ($lv_field =~ m%^stripes=(.*)%);
            $lv_alloc   = $1 if ($lv_field =~ m%^allocation=(.*)%);
            $lv_size    = $1 if ($lv_field =~ m%^lv_size=(.*)%);
        }
        # convert to GB if needed
        $lv_size /= 1024 unless ($options{'size'} =~ /MB/i);
        # report data
        printf STDOUT ("%-30s %-12s %-17s %-7d %-17s %-7s %-2s %-5s\n",
                ${lv_name},
                ${vg_name},
                ${lv_status},
                ${lv_size},
                ${lv_perm},
                ${lv_mirrors},
                ${lv_stripes},
                ${lv_alloc})
    }
}

# footer
$footer = qq{
Note 1: 'Size' values are expressed in GB by default (see --help)
Note 2: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

};
print STDOUT $footer;

exit (0);

#******************************************************************************
# End of SCRIPT
#******************************************************************************
__END__
#******************************************************************************
# POD
#******************************************************************************

# -----------------------------------------------------------------------------

=head1 NAME

lvs.pl - Show logical volume information in a terse way (Linux style).

=head1 SYNOPSIS

    lvs.pl [-h|--help] 
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -g | --vg

S<       >Display logical volumes for a specific volume group.

=item -s | --size

S<       >Show logical volume size in MB or GB (default is GB).

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

@(#) 2016-04-12: VRF 1.0.0: first version [Patrick Van der Veken]