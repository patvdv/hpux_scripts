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
use Data::Dumper;
$|++;


#******************************************************************************
# DATA structures
#******************************************************************************

my ($os, $version, $footer, $warning);
my $warn_devices = 500;
my %options;
my (@pvol, @cvol, @vgdisplay);
my %cdsf;

#******************************************************************************
# SUBroutines
#******************************************************************************

sub parse_pvols {

    my @pvol = @_;
    my $pv_command;
    my %pvdisplay;
    my @dsf;

    unless (@pvol) {
        print "-- no disks found --\n";
        return;
    }

    # collect DSF/cDSF & pvol info
    foreach my $pvol (@pvol) {

        my (@dsf_data, @cdsf_data);
        my ($dsf, $cdsf, $is_cdsf) = ("","",0);

        chomp ($pvol);

        # check for DSF or cDSF?
        if ($pvol =~ m/cdisk/) {
            $pvol =~ s#cdisk/##;
            $is_cdsf = 1;
            # we have the cDSF, get the DSF (should only be 1!)
            @dsf_data = grep (/rcdisk\/${pvol}:/, @cvol);
            ($dsf) = (split (/:/, $dsf_data[0]))[1];
            $dsf =~ s#/dev/rdisk/## if (defined ($dsf));
            # save the cDSF
            push (@{$cdsf{$dsf}}, $pvol);
        } else {
            # we have the DSF, get the cDSF (could be >1)
            @cdsf_data = grep (/rdisk\/${pvol}:/, @cvol);
            ($dsf = $pvol) =~ s#disk/## if (defined ($dsf));

            # set cDSF flag if we found cDSFs
            $is_cdsf = 1 if (@cdsf_data);
            
            # loop over cDSF data
            foreach my $cdsf_data (@cdsf_data) {

                ($cdsf) = (split (/:/, $cdsf_data))[0];
                $cdsf =~ s#/dev/rcdisk/##;
                # save the cDSF
                push (@{$cdsf{$dsf}}, $cdsf) if (defined ($cdsf));
            }
        }

        # pvdisplay on DSF/cDSF (must be correct one!) but record it under $dsf
        # no error handling here, error indicates: inactive/non-LVM stuff
        if ($is_cdsf) {
            # get info of the first cDSF
            @{$pvdisplay{$dsf}} = `/usr/sbin/pvdisplay -F /dev/cdisk/@{$cdsf{$dsf}}[0] 2>/dev/null`;
        } else {
            @{$pvdisplay{$dsf}} = `/usr/sbin/pvdisplay -F /dev/disk/${dsf} 2>/dev/null`;
        }
        push (@dsf, $dsf);
    }

    # display pvol data (sorted by their device number: diskYYYY)
    foreach my $dsf (sort { substr($a, 4) <=> substr($b, 4) } (@dsf)) {

        chomp ($dsf);

        my ($cdsf, $cdsf_bit) = ("","");

        # make cDSF bit
        if (defined (@{$cdsf{$dsf}})) {
            # display only the first cDSF! (in case of multiples)
            $cdsf = @{$cdsf{$dsf}}[0];
            $cdsf_bit = "(".scalar (@{$cdsf{$dsf}}).")";
        } else {
            $cdsf = "n/a";
        }

        if (@{$pvdisplay{$dsf}}) {

            # check for PV data
            foreach my $pv_entry (@{$pvdisplay{$dsf}}) {

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
                printf STDOUT ("%-12s %-10s %-4s %-25s %-20s %-7d %-8d %-8d %-8d\n",
                    $dsf,
                    $cdsf,
                    $cdsf_bit,
                    $vg_name,
                    $pv_status,
                    $pv_size_pe,
                    $pv_size,
                    $pv_free,
                    $pv_stale_pe)
            }
        } else {
            unless ($options{'active'}) {
                printf STDOUT ("%-12s %-10s %-4s %-25s %-20s\n",
                    $dsf,
                    $cdsf,
                    $cdsf_bit,
                    "n/a",
                    "not active/not LVM");
            }
        }
    }
}

sub print_header {

    unless ($options{'terse'}) {

        if (scalar (@pvol) > $warn_devices) {
            $warning = qq{
WARNING: You have more than $warn_devices disk devices on your system. Collecting the PV information will take some time...
        };
            print STDOUT "$warning";
        }

        printf STDOUT ("\n%-12s %-10s %-4s %-25s %-20s %-7s %-8s %-8s %-8s\n",
            "PV", "cDSF", "(#)", "VG", "Status", "PE Size", "PV Size", "PV Free", "Stale PE");
    }
}


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
                active|a
                terse|t
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
    if ($options{'vg'} =~ m#/dev#) {
        print STDERR "ERROR: do not specify your VG with '/dev/...'. Only use the short VG name\n\n";
        exit (0);
    }
    # force --active off
    delete $options{'active'};
};

# fetch cDSF map
@cvol = `/usr/sbin/ioscan -kFN -m cluster_dsf 2>/dev/null`;
die "ERROR: could not retrieve cDSF info" if ($?);

# fetch PVOLs (non-boot)
if ($options{'vg'}) {
    # pvols can be cluster-wide or regular disks here! (output: cdisk/diskXXXX or disk/diskYYYY)
    @pvol = `/usr/sbin/vgdisplay -vF "/dev/${options{'vg'}}" 2>/dev/null | grep "^pv_name"  | cut -f1 -d':' | cut -f2 -d'=' | cut -f3-4 -d '/'`;
    unless (@pvol) { die "ERROR: could not retrieve VG info for ${options{'vg'}}" };
    print_header;
    parse_pvols (@pvol);
} else {
    # output: diskYYYY
    @pvol = `/usr/sbin/ioscan -kFN -C disk 2>/dev/null | cut -f9,13 -d':' | tr -d ':'`;
    die "ERROR: could not retrieve ioscan info" if ($?);
    print_header;
    parse_pvols (@pvol);

    # fetch PVOLs (boot); output: diskYYYY
    unless ($options{'terse'}) { print "\n-- Boot disk(s):\n"; }
    @pvol = `/usr/sbin/lvlnboot -v 2>/dev/null | grep 'Boot Disk' | awk '{ print \$1 }' | cut -f4 -d '/'`;
    die "ERROR: could not retrieve boot info" if ($?);
    parse_pvols (@pvol);
}

# footer
unless ($options{'terse'}) {
    
    $footer = qq{
Note 1: 'PE Size' values are expressed in MB
Note 2: 'PV Size' & 'PV Free' values are expressed in GB by default (see --help)
Note 3: cDSF: only the first cluster-wide device is shown in case of multiples. The number of cDSF is displayed in
        parentheses following the cDSF name.
Note 4: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

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

pvs.pl - Show physical volume information in a terse way (Linux style).

=head1 SYNOPSIS

    pvs.pl [-h|--help]
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]
           [(-a|--active)]
           [(-t|--terse)]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -a | --active

S<       >Hide non-active and non-LVM disks. Cannot be used in conjunction with --vg.

=item -g | --vg

S<       >Display physical volumes for a specific volume group. Volume group name should be specified without the "/dev/" prefix.

=item -s | --size

S<       >Show physical volume size in MB or GB (default is GB).

=item -t | --terse

S<       >Do not show header and footer information.

=head1 NOTE

Collecting & displaying the data might take a considerable amount of time depending
on the amount of devices present on the system.

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

 @(#) 2016-04-12: first version [Patrick Van der Veken]
 @(#) 2016-04-27: small fixes [Patrick Van der Veken]
 @(#) 2016-04-27: show all PVOLs & option --active added [Patrick Van der Veken]
 @(#) 2017-12-12: added support for cluster disks, added --terse [Patrick Van der Veken]