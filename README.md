# HP-UX scripts

This is a small collection of HP-UX related scripts. YMMV in terms of usage.

* **check_ora_sap_mounts.pl** : is a fairly quick-and-dirty script to validate the mount options on remote Oracle filesystems in a typical SAP setup according to some of the best practices in a SAP/Oracle environment. For more documentation, read <http://www.kudos.be/2012/02/27/validating-mount-options-for-oracle-filesystems/>

* **control_pkg_db.sh** : provides a quick way to manually (de)-activate the disk resources (VxVM) of a cluster package created with the Serviceguard *ECMT Oracle Toolkit*. This can come in handy when the Serviceguard cluster (package) has become inconsistent/unstartable. For more documentation, read <http://www.kudos.be/2013/02/19/serviceguard-ecmt-oracle-mount-helper/>

* **handle_failed_lunpaths.sh** : shows and/or removes failed LUN paths on HP-UX using the `scsimgr` tool. For more documentation, read <http://www.kudos.be/2015/03/13/handle-failed-lunpaths/>

* **[pvs.pl/vgs.pl/lvs.pl](http://www.kudos.be/2016/04/16/hp-ux-lvm-scripts-in-linux-style/)**: show basic LVM information in Linux-style.

