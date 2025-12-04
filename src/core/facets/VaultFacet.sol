// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVaultFacet} from "../../interfaces/IVaultFacet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {LibReentrancyGuard} from "../../libraries/LibReentrancyGuard.sol";
import {IComplianceFacet} from "../../interfaces/IComplianceFacet.sol";
import {ISecurityFacet} from "../../interfaces/ISecurityFacet.sol";

/**
 * @title VaultFacet
 * @notice Complete ERC-4626 and ERC-1155 vault implementation with fees, access control, and compliance
 * @dev Implements tokenized vault standard with multi-asset support
 */
contract VaultFacet is IVaultFacet, IERC1155Receiver {
    using SafeERC20 for IERC20;

    struct VaultStorage {
        mapping(uint256 => Vault) vaults;
        mapping(uint256 => VaultConfig) vaultConfigs; // vaultId => config
        mapping(uint256 => mapping(address => uint256)) balances; // vaultId => user => shares
        mapping(uint256 => mapping(address => mapping(address => uint256))) allowances; // vaultId => owner => spender => amount
        mapping(uint256 => mapping(address => mapping(uint256 => uint256))) multiAssetBalances; // vaultId => user => tokenId => balance
        mapping(uint256 => address[]) multiAssetTokens; // vaultId => token addresses
        mapping(address => uint256) protocolFees; // token => accumulated fees
        mapping(uint256 => mapping(address => uint256)) vaultFees; // vaultId => token => accumulated fees
        uint256 vaultCount;
        uint256 defaultDepositFee; // Default deposit fee in basis points
        uint256 defaultWithdrawalFee; // Default withdrawal fee in basis points
        uint256 defaultManagementFee; // Default management fee per year in basis points
        address feeCollector;
    }

    struct VaultConfig {
        uint256 depositFee; // Deposit fee in basis points (0-10000)
        uint256 withdrawalFee; // Withdrawal fee in basis points (0-10000)
        uint256 managementFee; // Management fee per year in basis points
        uint256 lastFeeCollection; // Timestamp of last fee collection
        bool paused; // Vault-specific pause
        bool allowListEnabled; // Enable allowlist for deposits
        mapping(address => bool) allowedAddresses; // Allowlist addresses
    }

    bytes32 private constant VAULT_STORAGE_POSITION = keccak256("asle.vault.storage");
    uint256 private constant MAX_BPS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // Events
    event VaultPaused(uint256 indexed vaultId, bool paused);
    event FeeCollected(uint256 indexed vaultId, address token, uint256 amount);
    event ProtocolFeeCollected(address token, uint256 amount);
    event Approval(uint256 indexed vaultId, address indexed owner, address indexed spender, uint256 value);
    event MultiAssetDeposit(uint256 indexed vaultId, address indexed user, address token, uint256 tokenId, uint256 amount);
    event MultiAssetWithdraw(uint256 indexed vaultId, address indexed user, address token, uint256 tokenId, uint256 amount);

    function vaultStorage() internal pure returns (VaultStorage storage vs) {
        bytes32 position = VAULT_STORAGE_POSITION;
        assembly {
            vs.slot := position
        }
    }

    // ============ Modifiers ============

    modifier onlyVaultCreator() {
        LibAccessControl.requireRole(LibAccessControl.VAULT_CREATOR_ROLE, msg.sender);
        _;
    }

    modifier onlyAdmin() {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier whenVaultNotPaused(uint256 vaultId) {
        VaultStorage storage vs = vaultStorage();
        require(!vs.vaultConfigs[vaultId].paused, "VaultFacet: Vault is paused");
        _;
    }

    modifier nonReentrant() {
        LibReentrancyGuard.enter();
        _;
        LibReentrancyGuard.exit();
    }

    // ============ Vault Creation ============

    /**
     * @notice Create a new vault (ERC-4626 or ERC-1155)
     */
    function createVault(
        address asset,
        bool isMultiAsset
    ) external override returns (uint256 vaultId) {
        if (!isMultiAsset) {
            require(asset != address(0), "VaultFacet: Asset required for ERC-4626");
        }

        VaultStorage storage vs = vaultStorage();
        vaultId = vs.vaultCount;
        vs.vaultCount++;

        Vault storage vault = vs.vaults[vaultId];
        vault.asset = asset;
        vault.isMultiAsset = isMultiAsset;
        vault.totalAssets = 0;
        vault.totalSupply = 0;
        vault.active = true;

        // Set default configuration
        VaultConfig storage config = vs.vaultConfigs[vaultId];
        config.depositFee = vs.defaultDepositFee > 0 ? vs.defaultDepositFee : 0;
        config.withdrawalFee = vs.defaultWithdrawalFee > 0 ? vs.defaultWithdrawalFee : 0;
        config.managementFee = vs.defaultManagementFee > 0 ? vs.defaultManagementFee : 0;
        config.lastFeeCollection = block.timestamp;
        config.paused = false;
        config.allowListEnabled = false;

        emit VaultCreated(vaultId, asset, isMultiAsset);
    }

    // ============ ERC-4626 Functions ============

    /**
     * @notice Returns the asset token address
     */
    function asset(uint256 vaultId) external view returns (address) {
        return vaultStorage().vaults[vaultId].asset;
    }

    /**
     * @notice Returns total assets managed by vault
     */
    function totalAssets(uint256 vaultId) external view returns (uint256) {
        Vault storage vault = vaultStorage().vaults[vaultId];
        return vault.totalAssets;
    }

    /**
     * @notice Convert assets to shares
     */
    function convertToShares(
        uint256 vaultId,
        uint256 assets
    ) public view override returns (uint256 shares) {
        Vault storage vault = vaultStorage().vaults[vaultId];
        if (vault.totalSupply == 0) {
            shares = assets; // 1:1 for first deposit
        } else {
            shares = (assets * vault.totalSupply) / vault.totalAssets;
        }
    }

    /**
     * @notice Convert shares to assets
     */
    function convertToAssets(
        uint256 vaultId,
        uint256 shares
    ) public view override returns (uint256 assets) {
        Vault storage vault = vaultStorage().vaults[vaultId];
        if (vault.totalSupply == 0) {
            assets = 0;
        } else {
            assets = (shares * vault.totalAssets) / vault.totalSupply;
        }
    }

    /**
     * @notice Maximum assets that can be deposited
     */
    function maxDeposit(uint256 vaultId, address) external pure returns (uint256) {
        return type(uint256).max; // No deposit limit
    }

    /**
     * @notice Preview shares for deposit
     */
    function previewDeposit(uint256 vaultId, uint256 assets) external view returns (uint256) {
        VaultConfig storage config = vaultStorage().vaultConfigs[vaultId];
        uint256 assetsAfterFee = assets - (assets * config.depositFee / MAX_BPS);
        return convertToShares(vaultId, assetsAfterFee);
    }

    /**
     * @notice Deposit assets and receive shares
     */
    function deposit(
        uint256 vaultId,
        uint256 assets,
        address receiver
    ) external override whenVaultNotPaused(vaultId) nonReentrant returns (uint256 shares) {
        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        IComplianceFacet.ComplianceMode mode = complianceFacet.getVaultComplianceMode(vaultId);
        require(complianceFacet.canAccess(msg.sender, mode), "VaultFacet: Compliance check failed");

        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(!vault.isMultiAsset, "VaultFacet: Use multi-asset deposit for ERC-1155 vaults");
        require(assets > 0, "VaultFacet: Assets must be > 0");

        // Check allowlist if enabled
        VaultConfig storage config = vs.vaultConfigs[vaultId];
        if (config.allowListEnabled) {
            require(config.allowedAddresses[msg.sender], "VaultFacet: Address not allowed");
        }

        IERC20 assetToken = IERC20(vault.asset);
        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        // Calculate and collect deposit fee
        uint256 depositFeeAmount = (assets * config.depositFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - depositFeeAmount;
        
        if (depositFeeAmount > 0) {
            vs.vaultFees[vaultId][vault.asset] += depositFeeAmount;
        }

        shares = convertToShares(vaultId, assetsAfterFee);
        vault.totalAssets += assetsAfterFee;
        vault.totalSupply += shares;
        vs.balances[vaultId][receiver] += shares;

        emit Deposit(vaultId, receiver, assets, shares);
    }

    /**
     * @notice Maximum shares that can be minted
     */
    function maxMint(uint256 vaultId, address) external pure returns (uint256) {
        return type(uint256).max; // No mint limit
    }

    /**
     * @notice Preview assets needed to mint shares
     */
    function previewMint(uint256 vaultId, uint256 shares) external view returns (uint256) {
        VaultConfig storage config = vaultStorage().vaultConfigs[vaultId];
        uint256 assetsNeeded = convertToAssets(vaultId, shares);
        // Add deposit fee
        return assetsNeeded + (assetsNeeded * config.depositFee / (MAX_BPS - config.depositFee));
    }

    /**
     * @notice Mint shares for assets
     */
    function mint(uint256 vaultId, uint256 shares, address receiver) external whenVaultNotPaused(vaultId) nonReentrant returns (uint256 assets) {
        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        IComplianceFacet.ComplianceMode mode = complianceFacet.getVaultComplianceMode(vaultId);
        require(complianceFacet.canAccess(msg.sender, mode), "VaultFacet: Compliance check failed");

        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(!vault.isMultiAsset, "VaultFacet: Use multi-asset mint for ERC-1155 vaults");

        assets = previewMint(vaultId, shares);
        IERC20 assetToken = IERC20(vault.asset);
        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        // Calculate and collect deposit fee
        VaultConfig storage config = vs.vaultConfigs[vaultId];
        uint256 depositFeeAmount = (assets * config.depositFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - depositFeeAmount;
        
        if (depositFeeAmount > 0) {
            vs.vaultFees[vaultId][vault.asset] += depositFeeAmount;
        }

        vault.totalAssets += assetsAfterFee;
        vault.totalSupply += shares;
        vs.balances[vaultId][receiver] += shares;

        emit Deposit(vaultId, receiver, assets, shares);
    }

    /**
     * @notice Maximum assets that can be withdrawn
     */
    function maxWithdraw(uint256 vaultId, address owner) external view returns (uint256) {
        VaultStorage storage vs = vaultStorage();
        return convertToAssets(vaultId, vs.balances[vaultId][owner]);
    }

    /**
     * @notice Preview shares needed to withdraw assets
     */
    function previewWithdraw(uint256 vaultId, uint256 assets) external view returns (uint256) {
        VaultConfig storage config = vaultStorage().vaultConfigs[vaultId];
        uint256 assetsAfterFee = assets - (assets * config.withdrawalFee / MAX_BPS);
        return convertToShares(vaultId, assetsAfterFee);
    }

    /**
     * @notice Withdraw assets by burning shares
     */
    function withdraw(
        uint256 vaultId,
        uint256 shares,
        address receiver,
        address owner
    ) external override whenVaultNotPaused(vaultId) nonReentrant returns (uint256 assets) {
        // Check authorization
        if (msg.sender != owner) {
            VaultStorage storage vs = vaultStorage();
            uint256 allowed = vs.allowances[vaultId][owner][msg.sender];
            require(allowed >= shares, "VaultFacet: Insufficient allowance");
            vs.allowances[vaultId][owner][msg.sender] -= shares;
        }

        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(!vault.isMultiAsset, "VaultFacet: Use multi-asset withdraw for ERC-1155 vaults");
        require(shares > 0, "VaultFacet: Shares must be > 0");
        require(vs.balances[vaultId][owner] >= shares, "VaultFacet: Insufficient shares");

        assets = convertToAssets(vaultId, shares);
        require(assets <= vault.totalAssets, "VaultFacet: Insufficient assets");

        // Calculate and collect withdrawal fee
        VaultConfig storage config = vs.vaultConfigs[vaultId];
        uint256 withdrawalFeeAmount = (assets * config.withdrawalFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - withdrawalFeeAmount;

        if (withdrawalFeeAmount > 0) {
            vs.vaultFees[vaultId][vault.asset] += withdrawalFeeAmount;
        }

        // Update state
        vault.totalAssets -= assets;
        vault.totalSupply -= shares;
        vs.balances[vaultId][owner] -= shares;

        IERC20(vault.asset).safeTransfer(receiver, assetsAfterFee);

        emit Withdraw(vaultId, receiver, assets, shares);
    }

    /**
     * @notice Maximum shares that can be redeemed
     */
    function maxRedeem(uint256 vaultId, address owner) external view returns (uint256) {
        return vaultStorage().balances[vaultId][owner];
    }

    /**
     * @notice Preview assets for redeeming shares
     */
    function previewRedeem(uint256 vaultId, uint256 shares) external view returns (uint256) {
        VaultConfig storage config = vaultStorage().vaultConfigs[vaultId];
        uint256 assets = convertToAssets(vaultId, shares);
        uint256 withdrawalFeeAmount = (assets * config.withdrawalFee) / MAX_BPS;
        return assets - withdrawalFeeAmount;
    }

    /**
     * @notice Redeem shares for assets
     */
    function redeem(uint256 vaultId, uint256 shares, address receiver, address owner) external whenVaultNotPaused(vaultId) nonReentrant returns (uint256 assets) {
        // Check authorization
        if (msg.sender != owner) {
            VaultStorage storage vs = vaultStorage();
            uint256 allowed = vs.allowances[vaultId][owner][msg.sender];
            require(allowed >= shares, "VaultFacet: Insufficient allowance");
            vs.allowances[vaultId][owner][msg.sender] -= shares;
        }

        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(!vault.isMultiAsset, "VaultFacet: Use multi-asset redeem for ERC-1155 vaults");
        require(vs.balances[vaultId][owner] >= shares, "VaultFacet: Insufficient shares");

        assets = convertToAssets(vaultId, shares);

        // Calculate and collect withdrawal fee
        VaultConfig storage config = vs.vaultConfigs[vaultId];
        uint256 withdrawalFeeAmount = (assets * config.withdrawalFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - withdrawalFeeAmount;

        if (withdrawalFeeAmount > 0) {
            vs.vaultFees[vaultId][vault.asset] += withdrawalFeeAmount;
        }

        // Update state
        vault.totalAssets -= assets;
        vault.totalSupply -= shares;
        vs.balances[vaultId][owner] -= shares;

        IERC20(vault.asset).safeTransfer(receiver, assetsAfterFee);

        emit Withdraw(vaultId, receiver, assets, shares);
    }

    // ============ Approval Mechanism ============

    /**
     * @notice Approve spender to withdraw shares
     */
    function approve(uint256 vaultId, address spender, uint256 amount) external returns (bool) {
        VaultStorage storage vs = vaultStorage();
        vs.allowances[vaultId][msg.sender][spender] = amount;
        emit Approval(vaultId, msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Get approval amount
     */
    function allowance(uint256 vaultId, address owner, address spender) external view returns (uint256) {
        return vaultStorage().allowances[vaultId][owner][spender];
    }

    /**
     * @notice Get balance of shares
     */
    function balanceOf(uint256 vaultId, address account) external view returns (uint256) {
        return vaultStorage().balances[vaultId][account];
    }

    // ============ ERC-1155 Multi-Asset Functions ============

    /**
     * @notice Deposit multiple assets into ERC-1155 vault
     */
    function depositMultiAsset(
        uint256 vaultId,
        address token,
        uint256 tokenId,
        uint256 amount
    ) external whenVaultNotPaused(vaultId) nonReentrant {
        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        IComplianceFacet.ComplianceMode mode = complianceFacet.getVaultComplianceMode(vaultId);
        require(complianceFacet.canAccess(msg.sender, mode), "VaultFacet: Compliance check failed");

        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(vault.isMultiAsset, "VaultFacet: Not a multi-asset vault");

        IERC1155(token).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        vs.multiAssetBalances[vaultId][msg.sender][tokenId] += amount;
        
        // Track token addresses
        bool tokenExists = false;
        for (uint i = 0; i < vs.multiAssetTokens[vaultId].length; i++) {
            if (vs.multiAssetTokens[vaultId][i] == token) {
                tokenExists = true;
                break;
            }
        }
        if (!tokenExists) {
            vs.multiAssetTokens[vaultId].push(token);
        }

        emit MultiAssetDeposit(vaultId, msg.sender, token, tokenId, amount);
    }

    /**
     * @notice Withdraw multiple assets from ERC-1155 vault
     */
    function withdrawMultiAsset(
        uint256 vaultId,
        address token,
        uint256 tokenId,
        uint256 amount
    ) external whenVaultNotPaused(vaultId) nonReentrant {
        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        require(vault.active, "VaultFacet: Vault not active");
        require(vault.isMultiAsset, "VaultFacet: Not a multi-asset vault");
        require(vs.multiAssetBalances[vaultId][msg.sender][tokenId] >= amount, "VaultFacet: Insufficient balance");

        vs.multiAssetBalances[vaultId][msg.sender][tokenId] -= amount;
        IERC1155(token).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        emit MultiAssetWithdraw(vaultId, msg.sender, token, tokenId, amount);
    }

    /**
     * @notice Get multi-asset balance
     */
    function getMultiAssetBalance(uint256 vaultId, address user, address token, uint256 tokenId) external view returns (uint256) {
        return vaultStorage().multiAssetBalances[vaultId][user][tokenId];
    }

    // ============ ERC-1155 Receiver ============

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ============ View Functions ============

    function getVault(uint256 vaultId) external view override returns (Vault memory) {
        return vaultStorage().vaults[vaultId];
    }

    // ============ Admin Functions ============

    /**
     * @notice Pause or unpause a vault
     */
    function setVaultPaused(uint256 vaultId, bool paused) external onlyAdmin {
        vaultStorage().vaultConfigs[vaultId].paused = paused;
        emit VaultPaused(vaultId, paused);
    }

    /**
     * @notice Set vault fees
     */
    function setVaultFees(uint256 vaultId, uint256 depositFee, uint256 withdrawalFee, uint256 managementFee) external onlyAdmin {
        require(depositFee <= 1000, "VaultFacet: Deposit fee too high");
        require(withdrawalFee <= 1000, "VaultFacet: Withdrawal fee too high");
        require(managementFee <= 2000, "VaultFacet: Management fee too high");
        
        VaultConfig storage config = vaultStorage().vaultConfigs[vaultId];
        config.depositFee = depositFee;
        config.withdrawalFee = withdrawalFee;
        config.managementFee = managementFee;
    }

    /**
     * @notice Collect management fees
     */
    function collectManagementFees(uint256 vaultId) external {
        VaultStorage storage vs = vaultStorage();
        Vault storage vault = vs.vaults[vaultId];
        VaultConfig storage config = vs.vaultConfigs[vaultId];

        uint256 timeElapsed = block.timestamp - config.lastFeeCollection;
        uint256 feeAmount = (vault.totalAssets * config.managementFee * timeElapsed) / (MAX_BPS * SECONDS_PER_YEAR);
        
        if (feeAmount > 0 && feeAmount < vault.totalAssets) {
            vs.vaultFees[vaultId][vault.asset] += feeAmount;
            vault.totalAssets -= feeAmount;
        }

        config.lastFeeCollection = block.timestamp;
    }

    /**
     * @notice Collect vault fees
     */
    function collectVaultFees(uint256 vaultId, address token) external onlyAdmin {
        VaultStorage storage vs = vaultStorage();
        uint256 amount = vs.vaultFees[vaultId][token];
        require(amount > 0, "VaultFacet: No fees to collect");
        
        vs.vaultFees[vaultId][token] = 0;
        IERC20(token).safeTransfer(vs.feeCollector != address(0) ? vs.feeCollector : msg.sender, amount);
        
        emit FeeCollected(vaultId, token, amount);
    }
}
