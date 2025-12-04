// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IComplianceFacet {
    enum ComplianceMode {
        Regulated,      // Mode A: Full KYC/AML
        Fintech,        // Mode B: Tiered KYC
        Decentralized   // Mode C: No KYC
    }

    struct UserCompliance {
        ComplianceMode mode;
        bool kycVerified;
        bool amlVerified;
        uint256 tier;
        bool active;
    }

    event ComplianceModeSet(
        address indexed user,
        ComplianceMode mode
    );

    event KYCVerified(
        address indexed user,
        bool verified
    );

    event OFACCheck(
        address indexed user,
        bool sanctioned
    );

    event TravelRuleCompliance(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 transactionHash
    );

    event ISO20022Message(
        address indexed user,
        string messageType,
        bytes32 messageId
    );

    function setUserComplianceMode(
        address user,
        ComplianceMode mode
    ) external;

    function verifyKYC(address user, bool verified) external;

    function verifyAML(address user, bool verified) external;

    function getUserCompliance(
        address user
    ) external view returns (UserCompliance memory);

    function canAccess(
        address user,
        ComplianceMode requiredMode
    ) external view returns (bool);

    function setVaultComplianceMode(
        uint256 vaultId,
        ComplianceMode mode
    ) external;

    function getVaultComplianceMode(
        uint256 vaultId
    ) external view returns (ComplianceMode);

    function validateTransaction(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool);
}

