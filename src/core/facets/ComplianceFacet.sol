// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IComplianceFacet} from "../../interfaces/IComplianceFacet.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";

contract ComplianceFacet is IComplianceFacet {
    struct ComplianceStorage {
        mapping(address => UserCompliance) userCompliance;
        mapping(uint256 => ComplianceMode) vaultComplianceMode;
        mapping(address => bool) ofacSanctioned; // OFAC sanctions list
        mapping(bytes32 => bool) travelRuleTransactions; // FATF Travel Rule transaction tracking
        mapping(address => uint256) lastAuditTime;
        mapping(address => uint256) transactionCount; // Track transaction count per address
        mapping(address => uint256) dailyVolume; // Daily transaction volume
        mapping(address => uint256) lastDayReset; // Last day reset timestamp
        bool iso20022Enabled;
        bool travelRuleEnabled;
        bool automaticOFACCheck;
        uint256 travelRuleThreshold; // Minimum amount for Travel Rule (in wei)
    }

    bytes32 private constant COMPLIANCE_STORAGE_POSITION = keccak256("asle.compliance.storage");

    function complianceStorage() internal pure returns (ComplianceStorage storage cs) {
        bytes32 position = COMPLIANCE_STORAGE_POSITION;
        assembly {
            cs.slot := position
        }
    }

    modifier onlyComplianceAdmin() {
        LibAccessControl.requireRole(LibAccessControl.COMPLIANCE_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier requireCompliance(address user, ComplianceMode requiredMode) {
        require(this.canAccess(user, requiredMode), "ComplianceFacet: Compliance check failed");
        _;
    }

    function setUserComplianceMode(
        address user,
        ComplianceMode mode
    ) external override onlyComplianceAdmin {
        ComplianceStorage storage cs = complianceStorage();
        cs.userCompliance[user].mode = mode;
        cs.userCompliance[user].active = true;
        emit ComplianceModeSet(user, mode);
    }

    function verifyKYC(address user, bool verified) external override onlyComplianceAdmin {
        ComplianceStorage storage cs = complianceStorage();
        cs.userCompliance[user].kycVerified = verified;
        emit KYCVerified(user, verified);
    }

    function verifyAML(address user, bool verified) external override onlyComplianceAdmin {
        ComplianceStorage storage cs = complianceStorage();
        cs.userCompliance[user].amlVerified = verified;
    }

    function getUserCompliance(
        address user
    ) external view override returns (UserCompliance memory) {
        return complianceStorage().userCompliance[user];
    }

    function canAccess(
        address user,
        ComplianceMode requiredMode
    ) external view override returns (bool) {
        ComplianceStorage storage cs = complianceStorage();
        UserCompliance memory userComp = cs.userCompliance[user];
        
        if (!userComp.active) {
            return requiredMode == ComplianceMode.Decentralized;
        }

        if (requiredMode == ComplianceMode.Decentralized) {
            return true; // Anyone can access decentralized mode
        }

        if (requiredMode == ComplianceMode.Fintech) {
            return userComp.mode == ComplianceMode.Fintech || userComp.mode == ComplianceMode.Regulated;
        }

        if (requiredMode == ComplianceMode.Regulated) {
            return userComp.mode == ComplianceMode.Regulated && 
                   userComp.kycVerified && 
                   userComp.amlVerified;
        }

        return false;
    }

    function setVaultComplianceMode(
        uint256 vaultId,
        ComplianceMode mode
    ) external override onlyComplianceAdmin {
        ComplianceStorage storage cs = complianceStorage();
        cs.vaultComplianceMode[vaultId] = mode;
    }

    function getVaultComplianceMode(
        uint256 vaultId
    ) external view override returns (ComplianceMode) {
        ComplianceStorage storage cs = complianceStorage();
        return cs.vaultComplianceMode[vaultId];
    }

    // Phase 3: Enhanced Compliance Functions

    function checkOFACSanctions(address user) external view returns (bool) {
        return complianceStorage().ofacSanctioned[user];
    }

    function setOFACSanctioned(address user, bool sanctioned) external onlyComplianceAdmin {
        complianceStorage().ofacSanctioned[user] = sanctioned;
        emit IComplianceFacet.OFACCheck(user, sanctioned);
    }

    function recordTravelRule(
        address from,
        address to,
        uint256 amount,
        bytes32 transactionHash
    ) external {
        ComplianceStorage storage cs = complianceStorage();
        require(cs.travelRuleEnabled, "ComplianceFacet: Travel Rule not enabled");
        require(amount >= cs.travelRuleThreshold, "ComplianceFacet: Amount below Travel Rule threshold");
        
        cs.travelRuleTransactions[transactionHash] = true;
        emit IComplianceFacet.TravelRuleCompliance(from, to, amount, transactionHash);
    }

    function getTravelRuleStatus(bytes32 transactionHash) external view returns (bool) {
        return complianceStorage().travelRuleTransactions[transactionHash];
    }

    function setTravelRuleThreshold(uint256 threshold) external onlyComplianceAdmin {
        complianceStorage().travelRuleThreshold = threshold;
    }

    function recordISO20022Message(
        address user,
        string calldata messageType,
        bytes32 messageId
    ) external onlyComplianceAdmin {
        ComplianceStorage storage cs = complianceStorage();
        require(cs.iso20022Enabled, "ComplianceFacet: ISO 20022 not enabled");
        
        // Use events instead of storage for ISO messages (storage optimization)
        emit IComplianceFacet.ISO20022Message(user, messageType, messageId);
    }

    function enableISO20022(bool enabled) external onlyComplianceAdmin {
        complianceStorage().iso20022Enabled = enabled;
    }

    function enableTravelRule(bool enabled) external onlyComplianceAdmin {
        complianceStorage().travelRuleEnabled = enabled;
    }

    function recordAudit(address user) external onlyComplianceAdmin {
        complianceStorage().lastAuditTime[user] = block.timestamp;
    }

    function getLastAuditTime(address user) external view returns (uint256) {
        return complianceStorage().lastAuditTime[user];
    }

    function validateTransaction(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool) {
        ComplianceStorage storage cs = complianceStorage();
        
        // Automatic OFAC sanctions check
        if (cs.automaticOFACCheck || cs.ofacSanctioned[from] || cs.ofacSanctioned[to]) {
            if (cs.ofacSanctioned[from] || cs.ofacSanctioned[to]) {
                return false;
            }
        }

        // Check compliance modes
        UserCompliance memory fromComp = cs.userCompliance[from];
        UserCompliance memory toComp = cs.userCompliance[to];

        // Both parties must meet minimum compliance requirements
        if (fromComp.mode == ComplianceMode.Regulated || toComp.mode == ComplianceMode.Regulated) {
            return fromComp.kycVerified && fromComp.amlVerified && 
                   toComp.kycVerified && toComp.amlVerified;
        }

        // Check Travel Rule requirements
        if (cs.travelRuleEnabled && amount >= cs.travelRuleThreshold) {
            // Travel Rule compliance should be checked separately via recordTravelRule
            // This is a basic validation
        }

        return true;
    }

    /**
     * @notice Automatic OFAC check on transaction (called by other facets)
     */
    function performAutomaticOFACCheck(address user) external view returns (bool) {
        ComplianceStorage storage cs = complianceStorage();
        if (cs.automaticOFACCheck) {
            // In production, this would call an external service or oracle
            // For now, just check the stored list
            return !cs.ofacSanctioned[user];
        }
        return true;
    }

    /**
     * @notice Batch set OFAC sanctions
     */
    function batchSetOFACSanctions(address[] calldata users, bool[] calldata sanctioned) external onlyComplianceAdmin {
        require(users.length == sanctioned.length, "ComplianceFacet: Arrays length mismatch");
        ComplianceStorage storage cs = complianceStorage();
        for (uint i = 0; i < users.length; i++) {
            cs.ofacSanctioned[users[i]] = sanctioned[i];
            emit IComplianceFacet.OFACCheck(users[i], sanctioned[i]);
        }
    }

    /**
     * @notice Enable/disable automatic OFAC checking
     */
    function setAutomaticOFACCheck(bool enabled) external onlyComplianceAdmin {
        complianceStorage().automaticOFACCheck = enabled;
    }

    /**
     * @notice Get transaction statistics for address
     */
    function getTransactionStats(address user) external view returns (uint256 count, uint256 dailyVol) {
        ComplianceStorage storage cs = complianceStorage();
        // Reset daily volume if new day
        if (block.timestamp >= cs.lastDayReset[user] + 1 days) {
            dailyVol = 0;
        } else {
            dailyVol = cs.dailyVolume[user];
        }
        return (cs.transactionCount[user], dailyVol);
    }

    /**
     * @notice Record transaction for compliance tracking
     */
    function recordTransaction(address from, address, uint256 amount) external {
        ComplianceStorage storage cs = complianceStorage();
        
        // Reset daily volume if new day
        if (block.timestamp >= cs.lastDayReset[from] + 1 days) {
            cs.dailyVolume[from] = 0;
            cs.lastDayReset[from] = block.timestamp;
        }
        
        cs.transactionCount[from]++;
        cs.dailyVolume[from] += amount;
    }
}

