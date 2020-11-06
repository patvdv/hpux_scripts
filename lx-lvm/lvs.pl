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
use POSIX qw(uname ceil);
use Getopt::Long;
use Pod::Usage;
$|++;


#******************************************************************************
# DATA structures
#******************************************************************************

my ($os, $version, $footer);
my %options;
my (@vgdisplay, @lvdisplay, @df);
my $lv_str_size=25;
my $vg_str_size=15;
my $fs_str_size=20;


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
                terse|t
                fs|f
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
if ($options{'vg'}) {
    $options{'vg'} =~ s#/dev/##;
};

# fetch LVOLs
if ($options{'vg'}) {
    @vgdisplay = `/usr/sbin/vgdisplay -vF ${options{'vg'}} 2>/dev/null | grep "^lv_name"`;
} else {
    @vgdisplay = `/usr/sbin/vgdisplay -vF 2>/dev/null | grep "^lv_name"`;
}
die "ERROR: could not retrieve VG info for $options{'vg'}" if ($?);

# fetch FS
if ($options{'fs'}) {
    @df = `/usr/bin/df -Pkls`;
    die "ERROR: could not retrieve FS info for $options{'df'}" if ($?);
}

# find max display size for LV & VG names
@lvdisplay = `ls -1 /dev/vg*/l* 2>/dev/null`;
foreach my $lv_entry (@lvdisplay) {

    my $str_size = 0; my @vg_entry;

    $str_size = length ($lv_entry);
    $lv_str_size = $str_size if ($str_size > $lv_str_size);

    @vg_entry = split ('/', $lv_entry);
    $str_size = length ($vg_entry[2]);
    $vg_str_size = $str_size if ($str_size > $vg_str_size);
}
# find max display size for FS names
foreach my $df_entry (@df) {

    my $str_size = 0; my @df_entry;

    my @fs_data = split (' ', $df_entry);
    $str_size = length ($fs_data[5]);
    $fs_str_size = $str_size if ($str_size > $fs_str_size);
}

# print header
unless ($options{'terse'}) {

    if ($options{'fs'}) {
        printf STDOUT ("\n%-${lv_str_size}s %-${vg_str_size}s %-17s %-7s %-10s %-${fs_str_size}s %-10s %-10s\n",
            "LV", "VG", "Status", "Size", "Extents", "Filesystem", "FS size", "FS free");
    } else {
        printf STDOUT ("\n%-${lv_str_size}s %-${vg_str_size}s %-17s %-7s %-7s %-17s %-7s %-8s %-18s\n",
            "LV", "VG", "Status", "Size", "Extents", "Permissions", "Mirrors", "Stripes", "Allocation");
    }
}

# loop over LVOLs (ASCII sorted)
foreach my $lvol (sort (@vgdisplay)) {

    my $lv_name = (split (/=/, (split (/:/, $lvol))[0]))[1];

    @lvdisplay = `/usr/sbin/lvdisplay -F ${lv_name} 2>/dev/null`;
    die "failed to execute: $!" if ($?);

    # loop over lvdisplay
    foreach my $lv_entry (@lvdisplay) {

        my ($vg_name, $lv_status, $lv_perm, $lv_alloc, $fs_name) = ("","","","","");
        my ($lv_mirrors, $lv_stripes, $lv_size, $lv_extent, $fs_size, $fs_free) = (0,0,0,0,0,0);

        my @lv_data = split (/:/, $lv_entry);

        # loop over LVOL data
        foreach my $lv_field (@lv_data) {

            $vg_name    = $1 if ($lv_field =~ m%^lv_name=/dev/(.*)/%);
            $lv_status  = $1 if ($lv_field =~ m%^lv_status=(.*)%);
            $lv_size    = $1 if ($lv_field =~ m%^lv_size=(.*)%);
            $lv_extent  = $1 if ($lv_field =~ m%^current_le=(.*)%);
            if (!defined ($options{'fs'})) {
                $lv_perm    = $1 if ($lv_field =~ m%^lv_permission=(.*)%);
                $lv_mirrors = $1 if ($lv_field =~ m%^mirror_copies=(.*)%);
                $lv_stripes = $1 if ($lv_field =~ m%^stripes=(.*)%);
                $lv_alloc   = $1 if ($lv_field =~ m%^allocation=(.*)%);
            }
        }
        if ($options{'fs'}) {
            # get fs name
            foreach my $df_line (@df) {

                my @fs_data = split (' ', $df_line);
                ($fs_size, $fs_free, $fs_name) = @fs_data[1,3,5] if ($df_line =~ m/^$lv_name /);
            }
            $fs_name = "-" if ($fs_name eq "");
            # convert to MB or GB
            if ($fs_size) {
                if ($options{'size'} =~ /MB/i) {
                    $fs_size = $fs_size / 1024;
                } else {
                    $fs_size = $fs_size / 1024 / 1024;
                }
                $fs_size = ceil ($fs_size);
            } else {
                $fs_size = '0';
            }
            if ($fs_free) {
                if ($options{'size'} =~ /MB/i) {
                    $fs_free = $fs_free / 1024;
                } else {
                    $fs_free = $fs_free / 1024 / 1024;
                }
                $fs_free = ceil ($fs_free);
            } else {
                $fs_free = '0';
            }
        }
        # convert to GB if needed
        $lv_size /= 1024 unless ($options{'size'} =~ /MB/i);
        $lv_size = ceil ($lv_size);

        # report data
        if ($options{'fs'}) {
            printf STDOUT ("%-${lv_str_size}s %-${vg_str_size}s %-17s %-7d %-10d %-${fs_str_size}s %-10d %-10d\n",
                $lv_name,
                $vg_name,
                $lv_status,
                $lv_size,
                $lv_extent,
                $fs_name,
                $fs_size,
                $fs_free)
        } else {
            printf STDOUT ("%-${lv_str_size}s %-${vg_str_size}s %-17s %-7d %-7d %-17s %-7s %-8s %-18s\n",
                $lv_name,
                $vg_name,
                $lv_status,
                $lv_size,
                $lv_extent,
                $lv_perm,
                $lv_mirrors,
                $lv_stripes,
                $lv_alloc)
        }
    }
}

# footer
unless ($options{'terse'}) {

    $footer = qq{
Note 1: 'Size' values are expressed in GB by default and may contain rounding errors (see --help)
Note 2: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

};
    print STDOUT $footer;
}

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

lvs.pl - Show logical volume (and some filesystem) information in a terse way (Linux style).

=head1 SYNOPSIS

    lvs.pl [-h|--help]
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]
           [(-f|--fs]
           [(-t|--terse)]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -g | --vg

S<       >Display logical volumes for a specific volume group.

=item -s | --size

S<       >Show logical volume size in MB or GB (default is GB).

=item -f | --fs

S<       >Show filesystem mountpoint & data (if mounted). Hides logical volume data such as mirrors, stripes, allocation etc.

=item -t | --terse

S<       >Do not show header and footer information.

=back

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

 @(#) 2016-04-12: first version [Patrick Van der Veken]
 @(#) 2016-04-27: small fixes [Patrick Van der Veken]
 @(#) 2016-06-27: added LV extents [Patrick Van der Veken]
 @(#) 2017-12-12: made LV+VG names display size dynamic, added --terse [Patrick Van der Veken]
 @(#) 2019-02-08: remove /dev/ prefix for VG [Patrick Van der Veken]
 @(#) 2020-03-26: use ceil() to round up to more sensible numbers [Patrick Van der Veken]
 @(#) 2020-11-02: add support for --fs toggle [Patrick Van der Veken]
