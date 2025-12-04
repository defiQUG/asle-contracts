// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LibAccessControl
 * @notice Diamond-compatible access control library using Diamond storage pattern
 * @dev Provides role-based access control for Diamond facets
 */
library LibAccessControl {
    bytes32 constant ACCESS_CONTROL_STORAGE_POSITION = keccak256("asle.accesscontrol.storage");
    bytes32 constant TIMELOCK_STORAGE_POSITION = keccak256("asle.timelock.storage");

    // Role definitions
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant POOL_CREATOR_ROLE = keccak256("POOL_CREATOR_ROLE");
    bytes32 public constant VAULT_CREATOR_ROLE = keccak256("VAULT_CREATOR_ROLE");
    bytes32 public constant COMPLIANCE_ADMIN_ROLE = keccak256("COMPLIANCE_ADMIN_ROLE");
    bytes32 public constant GOVERNANCE_ADMIN_ROLE = keccak256("GOVERNANCE_ADMIN_ROLE");
    bytes32 public constant SECURITY_ADMIN_ROLE = keccak256("SECURITY_ADMIN_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    struct AccessControlStorage {
        mapping(bytes32 => RoleData) roles;
        address[] roleMembers; // For enumeration support
    }

    struct TimelockStorage {
        mapping(bytes32 => uint256) scheduledOperations; // operationId => executionTime
        uint256 defaultDelay; // Default timelock delay in seconds
        bool timelockEnabled;
    }

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event OperationScheduled(bytes32 indexed operationId, uint256 executionTime);
    event OperationExecuted(bytes32 indexed operationId);

    function accessControlStorage() internal pure returns (AccessControlStorage storage acs) {
        bytes32 position = ACCESS_CONTROL_STORAGE_POSITION;
        assembly {
            acs.slot := position
        }
    }

    function timelockStorage() internal pure returns (TimelockStorage storage ts) {
        bytes32 position = TIMELOCK_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }

    /**
     * @notice Check if an account has a specific role
     */
    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return accessControlStorage().roles[role].members[account];
    }

    /**
     * @notice Check if account has role or is admin of role
     */
    function hasRoleOrAdmin(bytes32 role, address account) internal view returns (bool) {
        AccessControlStorage storage acs = accessControlStorage();
        return acs.roles[role].members[account] || hasRole(getRoleAdmin(role), account);
    }

    /**
     * @notice Get the admin role for a given role
     */
    function getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        AccessControlStorage storage acs = accessControlStorage();
        bytes32 adminRole = acs.roles[role].adminRole;
        return adminRole == bytes32(0) ? DEFAULT_ADMIN_ROLE : adminRole;
    }

    /**
     * @notice Grant a role to an account
     * @dev Can only be called by accounts with admin role
     */
    function grantRole(bytes32 role, address account) internal {
        AccessControlStorage storage acs = accessControlStorage();
        bytes32 adminRole = getRoleAdmin(role);
        require(hasRole(adminRole, msg.sender), "LibAccessControl: account is missing admin role");
        
        if (!acs.roles[role].members[account]) {
            acs.roles[role].members[account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /**
     * @notice Revoke a role from an account
     * @dev Can only be called by accounts with admin role
     */
    function revokeRole(bytes32 role, address account) internal {
        AccessControlStorage storage acs = accessControlStorage();
        bytes32 adminRole = getRoleAdmin(role);
        require(hasRole(adminRole, msg.sender), "LibAccessControl: account is missing admin role");
        
        if (acs.roles[role].members[account]) {
            acs.roles[role].members[account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /**
     * @notice Set the admin role for a role
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        AccessControlStorage storage acs = accessControlStorage();
        bytes32 previousAdminRole = getRoleAdmin(role);
        require(hasRole(previousAdminRole, msg.sender), "LibAccessControl: account is missing admin role");
        
        acs.roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @notice Require that account has role, revert if not
     */
    function requireRole(bytes32 role, address account) internal view {
        require(hasRole(role, account), "LibAccessControl: account is missing role");
    }

    /**
     * @notice Initialize access control with default admin
     */
    function initializeAccessControl(address defaultAdmin) internal {
        AccessControlStorage storage acs = accessControlStorage();
        require(!acs.roles[DEFAULT_ADMIN_ROLE].members[defaultAdmin], "LibAccessControl: already initialized");
        
        acs.roles[DEFAULT_ADMIN_ROLE].members[defaultAdmin] = true;
        
        // Set role hierarchies
        acs.roles[POOL_CREATOR_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        acs.roles[VAULT_CREATOR_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        acs.roles[COMPLIANCE_ADMIN_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        acs.roles[GOVERNANCE_ADMIN_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        acs.roles[SECURITY_ADMIN_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        acs.roles[FEE_COLLECTOR_ROLE].adminRole = DEFAULT_ADMIN_ROLE;
        
        emit RoleGranted(DEFAULT_ADMIN_ROLE, defaultAdmin, address(0));
    }

    // ============ Timelock Functions ============

    /**
     * @notice Schedule an operation with timelock
     */
    function scheduleOperation(bytes32 operationId, bytes32) internal {
        TimelockStorage storage ts = timelockStorage();
        require(ts.timelockEnabled, "LibAccessControl: timelock not enabled");
        require(ts.scheduledOperations[operationId] == 0, "LibAccessControl: operation already scheduled");
        
        uint256 executionTime = block.timestamp + ts.defaultDelay;
        ts.scheduledOperations[operationId] = executionTime;
        
        emit OperationScheduled(operationId, executionTime);
    }

    /**
     * @notice Check if operation is ready to execute
     */
    function isOperationReady(bytes32 operationId) internal view returns (bool) {
        TimelockStorage storage ts = timelockStorage();
        if (!ts.timelockEnabled) return true;
        
        uint256 executionTime = ts.scheduledOperations[operationId];
        return executionTime > 0 && block.timestamp >= executionTime;
    }

    /**
     * @notice Execute a scheduled operation
     */
    function executeOperation(bytes32 operationId) internal {
        TimelockStorage storage ts = timelockStorage();
        require(isOperationReady(operationId), "LibAccessControl: operation not ready");
        
        delete ts.scheduledOperations[operationId];
        emit OperationExecuted(operationId);
    }

    /**
     * @notice Cancel a scheduled operation
     */
    function cancelOperation(bytes32 operationId) internal {
        TimelockStorage storage ts = timelockStorage();
        require(ts.scheduledOperations[operationId] > 0, "LibAccessControl: operation not scheduled");
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "LibAccessControl: must be admin");
        
        delete ts.scheduledOperations[operationId];
    }

    /**
     * @notice Set timelock delay
     */
    function setTimelockDelay(uint256 delay) internal {
        TimelockStorage storage ts = timelockStorage();
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "LibAccessControl: must be admin");
        ts.defaultDelay = delay;
    }

    /**
     * @notice Enable/disable timelock
     */
    function setTimelockEnabled(bool enabled) internal {
        TimelockStorage storage ts = timelockStorage();
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "LibAccessControl: must be admin");
        ts.timelockEnabled = enabled;
    }
}

