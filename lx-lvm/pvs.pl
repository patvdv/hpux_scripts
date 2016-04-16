#!/usr/bin/env perl
#******************************************************************************
# @(#) pvs.pl
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
# @(#) HISTORY: see perldoc 'pvs.pl'
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
my (@vgdisplay, @pvdisplay);


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
printf STDOUT ("\n%-20s %-10s %-15s %-7s %-8s %-8s %-8s\n", 
        "PV", "VG", "Status", "PE Size", "PV Size", "PV Free", "Stale PE");

# fetch LVOLs
if ($options{'vg'}) {
    @vgdisplay = `/usr/sbin/vgdisplay -vF ${options{'vg'}} | grep "^pv_name"`;
} else {
    @vgdisplay = `/usr/sbin/vgdisplay -vF | grep "^pv_name"`;
}
die "failed to execute: $!" if ($?);

# loop over PVOLs
foreach my $pvol (@vgdisplay) {
        
    my $pv_name = (split (/=/, (split (/:/, $pvol))[0]))[1];

    @pvdisplay = `/usr/sbin/pvdisplay -F ${pv_name}`;
    die "failed to execute: $!" if ($?);
    
    # loop over pvdisplay
    foreach my $pv_entry (@pvdisplay) {
        
        my ($vg_name, $pv_status)= ("","");
        my ($pv_total_pe, $pv_size_pe, $pv_free_pe, $pv_stale_pe) = (0,0,0,0);
        my ($pv_size, $pv_free) = (0,0);
    
        my @pv_data = split (/:/, $pv_entry);

        # loop over PVOL data
        foreach my $pv_field (@pv_data) {

            $vg_name     = $1 if ($pv_field =~ m%^vg_name=/dev/(.*)%);
            $pv_status   = $1 if ($pv_field =~ m%^pv_status=(.*)%);
            $pv_total_pe = $1 if ($pv_field =~ m%^total_pe=(.*)%);
            $pv_size_pe  = $1 if ($pv_field =~ m%^pe_size=(.*)%);
            $pv_free_pe  = $1 if ($pv_field =~ m%^free_pe=(.*)%);
            $pv_stale_pe = $1 if ($pv_field =~ m%^stale_pe=(.*)%);
        }
        # calculate sizes
        $pv_size = $pv_total_pe * $pv_size_pe;
        $pv_size /= 1024 unless ($options{'size'} =~ /MB/i);            
        $pv_free = $pv_free_pe * $pv_size_pe;
        $pv_free /= 1024 unless ($options{'size'} =~ /MB/i);

        # report data
        printf STDOUT ("%-20s %-10s %-15s %-7d %-8d %-8d %-8d\n",
                ${pv_name},
                ${vg_name},
                ${pv_status},
                ${pv_size_pe},
                ${pv_size},
                ${pv_free},
                ${pv_stale_pe})
    }
}

# footer
$footer = qq{
Note 1: 'PE Size' values are expressed in MB
Note 2: 'PV Size' & 'PV FRee' values are expressed in GB by default (see --help)
Note 3: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

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

pvs.pl - Show physical volume information in a terse way (Linux style).

=head1 SYNOPSIS

    pvs.pl [-h|--help] 
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -g | --vg

S<       >Display physical volumes for a specific volume group.

=item -s | --size

S<       >Show physical volume size in MB or GB (default is GB).

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

@(#) 2016-04-12: VRF 1.0.0: first version [Patrick Van der Veken]