# HP-UX scripts

This is a small collection of HP-UX related scripts. YMMV in terms of usage.

* **check_ora_sap_mounts** : is a fairly quick-and-dirty script to validate the mount options on remote Oracle filesystems in a typical SAP setup according to some of the best practices in a SAP/Oracle environment.

* **control_pkg_db** : provides a quick way to manually (de)-activate the disk resources (VxVM) of a cluster package created with the Serviceguard *ECMT Oracle Toolkit*. This can come in handy when the Serviceguard cluster (package) has become inconsistent/unstartable.

* **handle_failed_lunpaths.sh** : shows and/or removes failed LUN paths on HP-UX using the `scsimgr` tool


