// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRWAFacet} from "../../interfaces/IRWAFacet.sol";
import {IERC1404} from "../../interfaces/IERC1404.sol";
import {IComplianceFacet} from "../../interfaces/IComplianceFacet.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RWAFacet is IRWAFacet, IERC1404 {
    using SafeERC20 for IERC20;

    struct RWAStorage {
        mapping(uint256 => RWA) rwas;
        mapping(uint256 => address) valueOracles; // tokenId => oracle address
        mapping(uint256 => bool) transferRestricted; // tokenId => restricted
        mapping(uint256 => uint256) lastValueUpdate; // tokenId => timestamp
        uint256 rwaCount;
    }

    // ERC-1404 restriction codes
    uint8 private constant SUCCESS = 0;
    uint8 private constant COMPLIANCE_FAILURE = 1;
    uint8 private constant HOLDER_NOT_VERIFIED = 2;
    uint8 private constant TRANSFER_RESTRICTED = 3;

    bytes32 private constant RWA_STORAGE_POSITION = keccak256("asle.rwa.storage");

    function rwaStorage() internal pure returns (RWAStorage storage rs) {
        bytes32 position = RWA_STORAGE_POSITION;
        assembly {
            rs.slot := position
        }
    }

    function tokenizeRWA(
        address assetContract,
        string calldata assetType,
        uint256 totalValue,
        bytes calldata
    ) external override returns (uint256 tokenId) {
        // Check compliance - RWA tokenization typically requires Regulated mode
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        require(
            complianceFacet.canAccess(msg.sender, IComplianceFacet.ComplianceMode.Regulated),
            "RWAFacet: Regulated compliance required"
        );

        RWAStorage storage rs = rwaStorage();
        tokenId = rs.rwaCount;
        rs.rwaCount++;

        RWA storage rwa = rs.rwas[tokenId];
        rwa.tokenId = tokenId;
        rwa.assetContract = assetContract;
        rwa.assetType = assetType;
        rwa.totalValue = totalValue;
        rwa.fractionalizedAmount = 0;
        rwa.active = true;
        rs.lastValueUpdate[tokenId] = block.timestamp;

        emit RWATokenized(tokenId, assetContract, assetType, totalValue);
    }

    function fractionalizeRWA(
        uint256 tokenId,
        uint256 amount,
        address recipient
    ) external override returns (uint256 shares) {
        RWAStorage storage rs = rwaStorage();
        RWA storage rwa = rs.rwas[tokenId];
        
        require(rwa.active, "RWAFacet: RWA not active");
        require(amount > 0, "RWAFacet: Amount must be > 0");
        require(rwa.fractionalizedAmount + amount <= rwa.totalValue, "RWAFacet: Exceeds total value");

        // Verify recipient compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        require(
            complianceFacet.canAccess(recipient, IComplianceFacet.ComplianceMode.Regulated),
            "RWAFacet: Recipient must have regulated compliance"
        );
        require(
            complianceFacet.validateTransaction(msg.sender, recipient, amount),
            "RWAFacet: Compliance validation failed"
        );
        
        rwa.fractionalizedAmount += amount;
        rwa.verifiedHolders[recipient] = true;

        shares = amount; // 1:1 for simplicity, could use different ratio

        emit RWAFractionalized(tokenId, recipient, amount);
    }

    function getRWA(uint256 tokenId) external view override returns (
        address assetContract,
        string memory assetType,
        uint256 totalValue,
        uint256 fractionalizedAmount,
        bool active
    ) {
        RWA storage rwa = rwaStorage().rwas[tokenId];
        return (
            rwa.assetContract,
            rwa.assetType,
            rwa.totalValue,
            rwa.fractionalizedAmount,
            rwa.active
        );
    }

    function verifyHolder(uint256 tokenId, address holder) external view override returns (bool) {
        return rwaStorage().rwas[tokenId].verifiedHolders[holder];
    }

    // ============ ERC-1404 Transfer Restrictions ============

    function detectTransferRestriction(address from, address to, uint256 amount) external view override returns (uint8) {
        // Find which RWA token this relates to (simplified - in production would need token mapping)
        RWAStorage storage rs = rwaStorage();
        
        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        if (!complianceFacet.validateTransaction(from, to, amount)) {
            return COMPLIANCE_FAILURE;
        }

        // Check holder verification for all RWAs
        // In production, would check specific token
        for (uint256 i = 0; i < rs.rwaCount; i++) {
            if (rs.transferRestricted[i]) {
                if (!rs.rwas[i].verifiedHolders[to]) {
                    return HOLDER_NOT_VERIFIED;
                }
            }
        }

        return SUCCESS;
    }

    function messageForTransferRestriction(uint8 restrictionCode) external pure override returns (string memory) {
        if (restrictionCode == COMPLIANCE_FAILURE) return "Transfer failed compliance check";
        if (restrictionCode == HOLDER_NOT_VERIFIED) return "Recipient not verified holder";
        if (restrictionCode == TRANSFER_RESTRICTED) return "Transfer restricted for this token";
        return "Transfer allowed";
    }

    // ============ Asset Value Management ============

    function updateAssetValue(uint256 tokenId, address oracle) external {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        RWAStorage storage rs = rwaStorage();
        rs.valueOracles[tokenId] = oracle;
        rs.lastValueUpdate[tokenId] = block.timestamp;
    }

    function getAssetValue(uint256 tokenId) external view returns (uint256) {
        RWAStorage storage rs = rwaStorage();
        address oracle = rs.valueOracles[tokenId];
        
        if (oracle == address(0)) {
            return rs.rwas[tokenId].totalValue;
        }

        try IOracle(oracle).latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            require(price > 0, "RWAFacet: Invalid oracle price");
            require(updatedAt > 0, "RWAFacet: Stale oracle data");
            return uint256(price);
        } catch {
            return rs.rwas[tokenId].totalValue; // Fallback to stored value
        }
    }

    function setTransferRestricted(uint256 tokenId, bool restricted) external {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        rwaStorage().transferRestricted[tokenId] = restricted;
    }
}


