#!/usr/bin/env perl
#******************************************************************************
# @(#) vgs.pl
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
# @(#) HISTORY: see perldoc 'vgs.pl'
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
my @vgdisplay;


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
printf STDOUT ("\n%-10s %-5s %-5s %-20s %-8s %-8s %-10s %-10s %-10s\n", 
        "VG", "PVs", "LVs", "Status", "Version", "PE Size", "VG Size", "VG Free", "VG Max");

# fetch vgdisplay
if ($options{'vg'}) {
    @vgdisplay = `/usr/sbin/vgdisplay -F ${options{'vg'}}`;
} else {
    @vgdisplay = `/usr/sbin/vgdisplay -F`;
}
die "failed to execute: $!" if ($?);


# loop over vgdisplay
foreach my $vg_entry (@vgdisplay) {
 
    my ($vg_name, $vg_status, $vg_version)= ("","","n/a");
    my ($vg_total_pe, $vg_size_pe, $vg_free_pe, $vg_cur_pvs, $vg_cur_lvs, $vg_max_pe) = (0,0,0,0,0,0);
    my ($vg_size, $vg_free, $vg_max) = (0,0,0);
    
    my @vg_data = split (/:/, $vg_entry);
    
    # loop over VG data
    foreach my $vg_field (@vg_data) {
    
        $vg_name   = $1 if ($vg_field =~ m%^vg_name=/dev/(.*)%);
        $vg_status = $1 if ($vg_field =~ m%^vg_status=(.*)%);

        unless ($vg_status eq "deactivated") {
            $vg_total_pe = $1 if ($vg_field =~ m%^total_pe=(.*)%);
            $vg_size_pe  = $1 if ($vg_field =~ m%^pe_size=(.*)%);
            $vg_free_pe  = $1 if ($vg_field =~ m%^free_pe=(.*)%);
            $vg_cur_pvs  = $1 if ($vg_field =~ m%^cur_pv=(.*)%);
            $vg_cur_lvs  = $1 if ($vg_field =~ m%^cur_lv=(.*)%);
            $vg_version  = $1 if ($vg_field =~ m%^vg_version=(.*)%);
            $vg_max_pe   = $1 if ($vg_field =~ m%^vg_max_extents=(.*)%);        
        }
    }
    # calculate sizes
    unless ($vg_status eq "deactivated") {
        $vg_size = $vg_total_pe * $vg_size_pe;
        $vg_size /= 1024 unless ($options{'size'} =~ /MB/i);            
        $vg_free = $vg_free_pe * $vg_size_pe;
        $vg_free /= 1024 unless ($options{'size'} =~ /MB/i);
        $vg_max = $vg_max_pe * $vg_size_pe;
        $vg_max /= 1024 unless ($options{'size'} =~ /MB/i); 
    }
    
    # report data
    printf STDOUT ("%-10s %-5s %-5s %-20s %-8s %-8d %-10d %-10d %-10d\n",
                ${vg_name},
                ${vg_cur_pvs},
                ${vg_cur_lvs},
                ${vg_status},
                ${vg_version},
                ${vg_size_pe},
                ${vg_size},
                ${vg_free},
                ${vg_max})
}

# footer
$footer = qq{
Note 1: 'PE Size' values are expressed in MB
Note 2: 'VG Size', 'VG Free', 'VG Max' values are expressed in GB by default (see --help)
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

vgs.pl - Show volume group information in a terse way (Linux style).

=head1 SYNOPSIS

    vgs.pl [-h|--help] 
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -g | --vg

S<       >Display information for a specific volume group.

=item -s | --size

S<       >Show volume group sizes in MB or GB (default is GB).

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

@(#) 2016-04-12: VRF 1.0.0: first version [Patrick Van der Veken]