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
use POSIX qw(uname ceil);
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
$|++;


#******************************************************************************
# DATA structures
#******************************************************************************

my ($os, $version, $footer);
my %options;
my @vgdisplay;
my @lsvg;
my %devs;
my $vg_str_size=15;


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
                pe|e
                pv|v
                active|a
                terse|t
            ));
}
# check options
if ($options{'help'}) {
    pod2usage(-verbose => 3);
    exit (0);
};
if ($options{'pe'} and $options{'pv'}) {
    pod2usage(-verbose => 3);
    exit (0);
};
unless ($options{'size'}) {
    $options{'size'} = 'GB';
};
if ($options{'vg'}) {
    $options{'vg'} =~ s#/dev/##;
    # force --active off
    delete $options{'active'};
};

# fetch vgdisplay
if ($options{'vg'}) {
    @vgdisplay = `/usr/sbin/vgdisplay -F ${options{'vg'}} 2>/dev/null`;
} else {
    @vgdisplay = `/usr/sbin/vgdisplay -F 2>/dev/null`;
}
die "ERROR: could not retrieve VG info for $options{'vg'}" if ($?);

# fetch dev numbers
if (!$options{'pe'}) {
    my $vg_field; my $vg_name;

    @lsvg = `/usr/bin/ls -l /dev/*/group 2>/dev/null`;
    foreach my $lsvg (@lsvg) {
        $vg_field = (split (/\s+/, $lsvg))[9];
        $vg_name  = (split (/\//, $vg_field))[2];
        if ($vg_name) {
            $devs{$vg_name}{'major'} = (split (/\s+/, $lsvg))[4];
            $devs{$vg_name}{'minor'} = (split (/\s+/, $lsvg))[5];
        }
    }
}

# find max display size for VG name
foreach my $vg_entry (@vgdisplay) {

    my @vg_data = split (/:/, $vg_entry);
    my $str_size = 0;

    # loop over VG data
    foreach my $vg_field (@vg_data) {
        $str_size = length ($1) if ($vg_field =~ m%^vg_name=/dev/(.*)%);
        $vg_str_size = $str_size if ($str_size > $vg_str_size);
    }
}

# print header
if ($options{'pe'}) {
    unless ($options{'terse'}) {
        printf STDOUT ("\n%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8s %-10s %-10s %-10s %-12s\n",
            "VG", "PVs", "LVs", "Status", "Version", "PE Size", "PE Total", "PE Alloc", "PE Free", "Max PE/PV");
    }
} elsif ($options{'pv'}) {
    unless ($options{'terse'}) {
        printf STDOUT ("\n%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8s %-8s %-8s %-12s\n",
            "VG", "PVs", "LVs", "Status", "Version", "Max PV", "Act PV", "PVGs", "Max PE/PV");
    }
} else {
    unless ($options{'terse'}) {
        printf STDOUT ("\n%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8s %-10s %-10s %-10s %-12s\n",
            "VG", "PVs", "LVs", "Status", "Version", "PE Size", "VG Size", "VG Free", "VG Max", "VG Major/Minor");
    }
}

# loop over vgdisplay (ASCII sorted)
foreach my $vg_entry (sort (@vgdisplay)) {

    my ($vg_name, $vg_status, $vg_version, $lsvg, $vg_major, $vg_minor,) = ("","","n/a","","n/a","n/a");
    my ($vg_total_pe, $vg_alloc_pe, $vg_size_pe, $vg_free_pe, $vg_cur_pvs, $vg_cur_lvs, $vg_max_pe, $vg_pe_per_pv) = (0,0,0,0,0,0,0,0);
    my ($vg_max_pv, $vg_act_pv, $vg_total_pvg) = (0,0,0);
    my ($vg_size, $vg_free, $vg_max) = (0,0,0);

    my @vg_data = split (/:/, $vg_entry);

    # loop over VG data
    foreach my $vg_field (@vg_data) {

        $vg_name   = $1 if ($vg_field =~ m%^vg_name=/dev/(.*)%);
        $vg_status = $1 if ($vg_field =~ m%^vg_status=(.*)%);

        unless ($vg_status eq "deactivated") {
            $vg_total_pe  = $1 if ($vg_field =~ m%^total_pe=(.*)%);
            $vg_alloc_pe  = $1 if ($vg_field =~ m%^alloc_pe=(.*)%);
            $vg_size_pe   = $1 if ($vg_field =~ m%^pe_size=(.*)%);
            $vg_free_pe   = $1 if ($vg_field =~ m%^free_pe=(.*)%);
            $vg_cur_pvs   = $1 if ($vg_field =~ m%^cur_pv=(.*)%);
            $vg_cur_lvs   = $1 if ($vg_field =~ m%^cur_lv=(.*)%);
            $vg_version   = $1 if ($vg_field =~ m%^vg_version=(.*)%);
            $vg_max_pe    = $1 if ($vg_field =~ m%^vg_max_extents=(.*)%);
            $vg_pe_per_pv = $1 if ($vg_field =~ m%^max_pe_per_pv=(.*)%);
            $vg_max_pv    = $1 if ($vg_field =~ m%^max_pv=(.*)%);
            $vg_act_pv    = $1 if ($vg_field =~ m%^act_pv=(.*)%);
            $vg_total_pvg = $1 if ($vg_field =~ m%^total_pvg=(.*)%);
        }
    }
    if (!$options{'pe'}) {
        # calculate sizes
        unless ($vg_status eq "deactivated") {
            $vg_size = $vg_total_pe * $vg_size_pe;
            $vg_size /= 1024 unless ($options{'size'} =~ /MB/i);
            $vg_size = ceil ($vg_size);
            $vg_free = $vg_free_pe * $vg_size_pe;
            $vg_free /= 1024 unless ($options{'size'} =~ /MB/i);
            $vg_free = ceil ($vg_free);
            $vg_max = $vg_max_pe * $vg_size_pe;
            $vg_max /= 1024 unless ($options{'size'} =~ /MB/i);
            $vg_max = ceil ($vg_max);
        }
        # get major/minor number
        $vg_major = $devs{$vg_name}{'major'} if ($devs{$vg_name}{'major'});
        $vg_minor = $devs{$vg_name}{'minor'} if ($devs{$vg_name}{'minor'});
    }

    # report data
    if ($options{'pe'}) {
        unless ($options{'active'} and ($vg_status eq "deactivated")) {
            printf STDOUT ("%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8d %-10d %-10d %-10d %-12d\n",
                $vg_name,
                $vg_cur_pvs,
                $vg_cur_lvs,
                $vg_status,
                $vg_version,
                $vg_size_pe,
                $vg_total_pe,
                $vg_alloc_pe,
                $vg_free_pe,
                $vg_pe_per_pv)
        }
    } elsif ($options{'pv'}) {
        unless ($options{'active'} and ($vg_status eq "deactivated")) {
            printf STDOUT ("%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8d %-8d %-8d %-12d\n",
                $vg_name,
                $vg_cur_pvs,
                $vg_cur_lvs,
                $vg_status,
                $vg_version,
                $vg_max_pv,
                $vg_act_pv,
                $vg_total_pvg,
                $vg_pe_per_pv)
        }
    } else {
        unless ($options{'active'} and ($vg_status eq "deactivated")) {
            printf STDOUT ("%-${vg_str_size}s %-5s %-5s %-20s %-8s %-8d %-10d %-10d %-10d %3s/%-8s\n",
                $vg_name,
                $vg_cur_pvs,
                $vg_cur_lvs,
                $vg_status,
                $vg_version,
                $vg_size_pe,
                $vg_size,
                $vg_free,
                $vg_max,
                $vg_major,
                $vg_minor)
        }
    }
}

# footer
unless ($options{'terse'}) {

    $footer = qq{
Note 1: 'PE Size' values are expressed in MB
Note 2: 'VG Size', 'VG Free', 'VG Max' values are expressed in GB by default (see --help)
Note 3: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

};
    print STDOUT $footer;
};

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
           [(-a|--active)]
           [(-e|--pe) | (-v|--pv)]
           [(-t|--terse)]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -a | --active

S<       >Hide non-active VGs. Cannot be used in conjunction with --vg.

=item -g | --vg

S<       >Display information for a specific volume group.

=item -s | --size

S<       >Show volume group sizes in MB or GB (default is GB).

=item -e | --pe

S<       >Show PE (physical extents) information instead of detailed VG (volume group) information

=item -v | --pv

S<       >Show PV  (physical volume) information instead of detailed VG (volume group) information

=item -t | --terse

S<       >Do not show header and footer information.

=back

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

 @(#) 2016-04-12: first version [Patrick Van der Veken]
 @(#) 2016-04-27: added 'VG Major/Minor' [Patrick Van der Veken]
 @(#) 2017-12-12: made VG name display size dynamic, added --active, added --terse [Patrick Van der Veken]
 @(#) 2019-02-08: remove /dev/ prefix for VG [Patrick Van der Veken]
 @(#) 2020-03-26: use ceil() to round up to more sensible numbers [Patrick Van der Veken]
 @(#) 2020-11-10: add support for --pe & --pv toggles [Patrick Van der Veken]
 @(#) 2020-11-12: made dev number discovery faster [Patrick Van der Veken]
