# DDD role: PolicyTest
package k8smanager.app_shell.single_instance_test

import future.keywords.if
import future.keywords.in
import data.k8smanager.app_shell.single_instance

# ---------------------------------------------------------------------------
# Allow tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_allow_valid_config if {
    single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-a1b2c3d4e5f60718",
    }
}

test_allow_all_hex_lowercase if {
    single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-deadbeef01234567",
    }
}

test_allow_all_numeric_lease_suffix if {
    single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-0000000000000001",
    }
}

# ---------------------------------------------------------------------------
# Deny tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_deny_multiple_instances_allowed if {
    not single_instance.allow with input as {
        "lsMultipleInstancesProhibited": false,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-a1b2c3d4e5f60718",
    }
}

test_deny_open_new_behavior if {
    not single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "open-new",
        "instanceLeaseKey": "k8smgr-instance-a1b2c3d4e5f60718",
    }
}

test_deny_invalid_lease_key_too_short if {
    not single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-abc",
    }
}

test_deny_uppercase_in_lease_key if {
    not single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-A1B2C3D4E5F60718",
    }
}

test_deny_terminate_new_behavior if {
    not single_instance.allow with input as {
        "lsMultipleInstancesProhibited": true,
        "secondInstanceBehavior": "terminate-new",
        "instanceLeaseKey": "k8smgr-instance-a1b2c3d4e5f60718",
    }
}

test_deny_violation_message_ls_plist if {
    msgs := single_instance.deny_violations with input as {
        "lsMultipleInstancesProhibited": false,
        "secondInstanceBehavior": "activate-existing",
        "instanceLeaseKey": "k8smgr-instance-a1b2c3d4e5f60718",
    }
    count(msgs) == 1
    some msg in msgs
    contains(msg, "LSMultipleInstancesProhibited")
}
