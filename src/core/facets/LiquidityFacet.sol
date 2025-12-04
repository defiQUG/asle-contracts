// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILiquidityFacet} from "../../interfaces/ILiquidityFacet.sol";
import {PMMMath} from "../../libraries/PMMMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibAccessControl} from "../../libraries/LibAccessControl.sol";
import {LibReentrancyGuard} from "../../libraries/LibReentrancyGuard.sol";
import {IComplianceFacet} from "../../interfaces/IComplianceFacet.sol";
import {ISecurityFacet} from "../../interfaces/ISecurityFacet.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

/**
 * @title LiquidityFacet
 * @notice Enhanced liquidity facet with PMM, fees, access control, and compliance
 * @dev This facet manages DODO PMM pools with comprehensive security features
 */
contract LiquidityFacet is ILiquidityFacet {
    using PMMMath for uint256;
    using SafeERC20 for IERC20;

    struct LiquidityStorage {
        mapping(uint256 => Pool) pools;
        mapping(uint256 => PoolConfig) poolConfigs; // poolId => config
        mapping(uint256 => mapping(address => uint256)) lpBalances; // poolId => user => lpShares
        mapping(uint256 => uint256) totalLPSupply; // poolId => total LP supply
        mapping(uint256 => address) priceFeeds; // poolId => Chainlink price feed
        mapping(address => uint256) protocolFees; // token => accumulated fees
        mapping(uint256 => mapping(address => uint256)) poolFees; // poolId => token => accumulated fees
        uint256 poolCount;
        uint256 defaultTradingFee; // Default trading fee in basis points (e.g., 30 = 0.3%)
        uint256 defaultProtocolFee; // Default protocol fee in basis points
        address feeCollector; // Address to receive protocol fees
    }

    struct PoolConfig {
        uint256 tradingFee; // Trading fee in basis points (0-10000)
        uint256 protocolFee; // Protocol fee in basis points (0-10000)
        bool paused; // Pool-specific pause
        address oracle; // Chainlink price feed address
        uint256 lastOracleUpdate; // Timestamp of last oracle update
        uint256 oracleUpdateInterval; // Minimum interval between oracle updates
    }

    bytes32 private constant LIQUIDITY_STORAGE_POSITION = keccak256("asle.liquidity.storage");

    // Events
    event PoolPaused(uint256 indexed poolId, bool paused);
    event OraclePriceUpdated(uint256 indexed poolId, uint256 newPrice);
    event TradingFeeCollected(uint256 indexed poolId, address token, uint256 amount);
    event ProtocolFeeCollected(address token, uint256 amount);
    event FeeCollectorUpdated(address newFeeCollector);
    event PoolFeeUpdated(uint256 indexed poolId, uint256 tradingFee, uint256 protocolFee);

    function liquidityStorage() internal pure returns (LiquidityStorage storage ls) {
        bytes32 position = LIQUIDITY_STORAGE_POSITION;
        assembly {
            ls.slot := position
        }
    }

    // ============ Access Control Modifiers ============

    modifier onlyPoolCreator() {
        LibAccessControl.requireRole(LibAccessControl.POOL_CREATOR_ROLE, msg.sender);
        _;
    }

    modifier onlyAdmin() {
        LibAccessControl.requireRole(LibAccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier whenPoolNotPaused(uint256 poolId) {
        LiquidityStorage storage ls = liquidityStorage();
        require(!ls.poolConfigs[poolId].paused, "LiquidityFacet: Pool is paused");
        _;
    }

    modifier nonReentrant() {
        LibReentrancyGuard.enter();
        _;
        LibReentrancyGuard.exit();
    }

    // ============ Pool Creation ============

    /**
     * @notice Create a new PMM liquidity pool (backward compatible with interface)
     */
    function createPool(
        address baseToken,
        address quoteToken,
        uint256 initialBaseReserve,
        uint256 initialQuoteReserve,
        uint256 virtualBaseReserve,
        uint256 virtualQuoteReserve,
        uint256 k,
        uint256 oraclePrice
    ) external override returns (uint256 poolId) {
        return _createPool(
            baseToken,
            quoteToken,
            initialBaseReserve,
            initialQuoteReserve,
            virtualBaseReserve,
            virtualQuoteReserve,
            k,
            oraclePrice,
            address(0)
        );
    }

    /**
     * @notice Create a new PMM liquidity pool with oracle
     */
    function createPoolWithOracle(
        address baseToken,
        address quoteToken,
        uint256 initialBaseReserve,
        uint256 initialQuoteReserve,
        uint256 virtualBaseReserve,
        uint256 virtualQuoteReserve,
        uint256 k,
        uint256 oraclePrice,
        address oracle
    ) external onlyPoolCreator returns (uint256 poolId) {
        return _createPool(
            baseToken,
            quoteToken,
            initialBaseReserve,
            initialQuoteReserve,
            virtualBaseReserve,
            virtualQuoteReserve,
            k,
            oraclePrice,
            oracle
        );
    }

    function _createPool(
        address baseToken,
        address quoteToken,
        uint256 initialBaseReserve,
        uint256 initialQuoteReserve,
        uint256 virtualBaseReserve,
        uint256 virtualQuoteReserve,
        uint256 k,
        uint256 oraclePrice,
        address oracle
    ) internal returns (uint256 poolId) {
        // Check if system is paused
        ISecurityFacet securityFacet = ISecurityFacet(address(this));
        require(!securityFacet.isPaused(), "LiquidityFacet: System is paused");

        require(baseToken != address(0) && quoteToken != address(0), "LiquidityFacet: Invalid tokens");
        require(baseToken != quoteToken, "LiquidityFacet: Tokens must be different");
        require(k <= 1e18, "LiquidityFacet: k must be <= 1");
        require(virtualBaseReserve > 0 && virtualQuoteReserve > 0, "LiquidityFacet: Virtual reserves must be > 0");
        require(oraclePrice > 0, "LiquidityFacet: Oracle price must be > 0");

        LiquidityStorage storage ls = liquidityStorage();
        poolId = ls.poolCount;
        ls.poolCount++;

        Pool storage pool = ls.pools[poolId];
        pool.baseToken = baseToken;
        pool.quoteToken = quoteToken;
        pool.baseReserve = initialBaseReserve;
        pool.quoteReserve = initialQuoteReserve;
        pool.virtualBaseReserve = virtualBaseReserve;
        pool.virtualQuoteReserve = virtualQuoteReserve;
        pool.k = k;
        pool.oraclePrice = oraclePrice;
        pool.active = true;

        // Set pool configuration
        PoolConfig storage config = ls.poolConfigs[poolId];
        config.tradingFee = ls.defaultTradingFee > 0 ? ls.defaultTradingFee : 30; // 0.3% default
        config.protocolFee = ls.defaultProtocolFee > 0 ? ls.defaultProtocolFee : 10; // 0.1% default
        config.paused = false;
        config.oracle = oracle;
        config.lastOracleUpdate = block.timestamp;
        config.oracleUpdateInterval = 3600; // 1 hour default

        // Transfer initial tokens
        if (initialBaseReserve > 0) {
            IERC20(baseToken).safeTransferFrom(msg.sender, address(this), initialBaseReserve);
        }
        if (initialQuoteReserve > 0) {
            IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), initialQuoteReserve);
        }

        emit PoolCreated(poolId, baseToken, quoteToken);
    }

    // ============ Liquidity Management ============

    /**
     * @notice Add liquidity to a pool
     */
    function addLiquidity(
        uint256 poolId,
        uint256 baseAmount,
        uint256 quoteAmount
    ) external override whenPoolNotPaused(poolId) nonReentrant returns (uint256 lpShares) {
        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        IComplianceFacet.ComplianceMode mode = complianceFacet.getVaultComplianceMode(poolId);
        require(complianceFacet.canAccess(msg.sender, mode), "LiquidityFacet: Compliance check failed");

        LiquidityStorage storage ls = liquidityStorage();
        Pool storage pool = ls.pools[poolId];
        require(pool.active, "LiquidityFacet: Pool not active");

        // Transfer tokens
        if (baseAmount > 0) {
            IERC20(pool.baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);
        }
        if (quoteAmount > 0) {
            IERC20(pool.quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmount);
        }

        // Calculate LP shares
        lpShares = PMMMath.calculateLPShares(
            baseAmount,
            quoteAmount,
            pool.baseReserve,
            pool.quoteReserve,
            ls.totalLPSupply[poolId]
        );

        // Update reserves
        pool.baseReserve += baseAmount;
        pool.quoteReserve += quoteAmount;
        ls.lpBalances[poolId][msg.sender] += lpShares;
        ls.totalLPSupply[poolId] += lpShares;

        emit LiquidityAdded(poolId, msg.sender, baseAmount, quoteAmount);
    }

    // ============ Swapping ============

    /**
     * @notice Execute a swap in the pool
     */
    function swap(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external override whenPoolNotPaused(poolId) nonReentrant returns (uint256 amountOut) {
        // Check security (circuit breaker)
        ISecurityFacet securityFacet = ISecurityFacet(address(this));
        require(securityFacet.checkCircuitBreaker(poolId, amountIn), "LiquidityFacet: Circuit breaker triggered");

        // Check compliance
        IComplianceFacet complianceFacet = IComplianceFacet(address(this));
        require(
            complianceFacet.validateTransaction(msg.sender, address(this), amountIn),
            "LiquidityFacet: Compliance validation failed"
        );

        LiquidityStorage storage ls = liquidityStorage();
        Pool storage pool = ls.pools[poolId];
        require(pool.active, "LiquidityFacet: Pool not active");
        require(tokenIn == pool.baseToken || tokenIn == pool.quoteToken, "LiquidityFacet: Invalid token");

        // Update oracle price if available and needed
        _updateOraclePrice(poolId);

        // Transfer input token
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        bool isBaseIn = (tokenIn == pool.baseToken);
        address tokenOut = isBaseIn ? pool.quoteToken : pool.baseToken;

        // Calculate output using PMM formula
        amountOut = PMMMath.calculateSwapOutput(
            amountIn,
            isBaseIn ? pool.baseReserve : pool.quoteReserve,
            isBaseIn ? pool.quoteReserve : pool.baseReserve,
            isBaseIn ? pool.virtualBaseReserve : pool.virtualQuoteReserve,
            isBaseIn ? pool.virtualQuoteReserve : pool.virtualBaseReserve,
            pool.k,
            pool.oraclePrice
        );

        require(amountOut >= minAmountOut, "LiquidityFacet: Slippage too high");

        // Calculate and collect fees
        PoolConfig storage config = ls.poolConfigs[poolId];
        uint256 tradingFeeAmount = (amountOut * config.tradingFee) / 10000;
        uint256 protocolFeeAmount = (tradingFeeAmount * config.protocolFee) / 10000;
        uint256 poolFeeAmount = tradingFeeAmount - protocolFeeAmount;

        amountOut -= tradingFeeAmount;

        // Update reserves (after fees)
        if (isBaseIn) {
            pool.baseReserve += amountIn;
            pool.quoteReserve -= (amountOut + tradingFeeAmount);
        } else {
            pool.quoteReserve += amountIn;
            pool.baseReserve -= (amountOut + tradingFeeAmount);
        }

        // Collect fees
        if (poolFeeAmount > 0) {
            ls.poolFees[poolId][tokenOut] += poolFeeAmount;
        }
        if (protocolFeeAmount > 0) {
            ls.protocolFees[tokenOut] += protocolFeeAmount;
        }

        // Transfer output token
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swap(poolId, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        emit TradingFeeCollected(poolId, tokenOut, tradingFeeAmount);
    }

    // ============ View Functions ============

    function getPool(uint256 poolId) external view override returns (Pool memory) {
        return liquidityStorage().pools[poolId];
    }

    function getPrice(uint256 poolId) external view override returns (uint256) {
        Pool memory pool = liquidityStorage().pools[poolId];
        return PMMMath.calculatePrice(
            pool.oraclePrice,
            pool.k,
            pool.quoteReserve,
            pool.virtualQuoteReserve
        );
    }

    function getQuote(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        Pool memory pool = liquidityStorage().pools[poolId];
        require(tokenIn == pool.baseToken || tokenIn == pool.quoteToken, "LiquidityFacet: Invalid token");
        
        bool isBaseIn = (tokenIn == pool.baseToken);
        amountOut = PMMMath.calculateSwapOutput(
            amountIn,
            isBaseIn ? pool.baseReserve : pool.quoteReserve,
            isBaseIn ? pool.quoteReserve : pool.baseReserve,
            isBaseIn ? pool.virtualBaseReserve : pool.virtualQuoteReserve,
            isBaseIn ? pool.virtualQuoteReserve : pool.virtualBaseReserve,
            pool.k,
            pool.oraclePrice
        );
    }

    // ============ Admin Functions ============

    /**
     * @notice Update oracle price for a pool
     */
    function updateOraclePrice(uint256 poolId) external {
        _updateOraclePrice(poolId);
    }

    function _updateOraclePrice(uint256 poolId) internal {
        LiquidityStorage storage ls = liquidityStorage();
        PoolConfig storage config = ls.poolConfigs[poolId];
        
        if (config.oracle == address(0)) return;
        if (block.timestamp < config.lastOracleUpdate + config.oracleUpdateInterval) return;

        try IOracle(config.oracle).latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            require(price > 0, "LiquidityFacet: Invalid oracle price");
            require(updatedAt > 0, "LiquidityFacet: Stale oracle data");
            
            Pool storage pool = ls.pools[poolId];
            pool.oraclePrice = uint256(price);
            config.lastOracleUpdate = block.timestamp;
            
            emit OraclePriceUpdated(poolId, uint256(price));
        } catch {
            // Oracle call failed, skip update
        }
    }

    /**
     * @notice Pause or unpause a pool
     */
    function setPoolPaused(uint256 poolId, bool paused) external onlyAdmin {
        LiquidityStorage storage ls = liquidityStorage();
        ls.poolConfigs[poolId].paused = paused;
        emit PoolPaused(poolId, paused);
    }

    /**
     * @notice Set pool fees
     */
    function setPoolFees(uint256 poolId, uint256 tradingFee, uint256 protocolFee) external onlyAdmin {
        require(tradingFee <= 1000, "LiquidityFacet: Trading fee too high"); // Max 10%
        require(protocolFee <= 5000, "LiquidityFacet: Protocol fee too high"); // Max 50% of trading fee
        
        LiquidityStorage storage ls = liquidityStorage();
        ls.poolConfigs[poolId].tradingFee = tradingFee;
        ls.poolConfigs[poolId].protocolFee = protocolFee;
        emit PoolFeeUpdated(poolId, tradingFee, protocolFee);
    }

    /**
     * @notice Set Chainlink oracle for a pool
     */
    function setPoolOracle(uint256 poolId, address oracle) external onlyAdmin {
        LiquidityStorage storage ls = liquidityStorage();
        ls.poolConfigs[poolId].oracle = oracle;
    }

    /**
     * @notice Collect protocol fees
     */
    function collectProtocolFees(address token) external {
        LiquidityStorage storage ls = liquidityStorage();
        address collector = ls.feeCollector != address(0) ? ls.feeCollector : msg.sender;
        require(collector == msg.sender || LibAccessControl.hasRole(LibAccessControl.FEE_COLLECTOR_ROLE, msg.sender), 
                "LiquidityFacet: Not authorized");
        
        uint256 amount = ls.protocolFees[token];
        require(amount > 0, "LiquidityFacet: No fees to collect");
        
        ls.protocolFees[token] = 0;
        IERC20(token).safeTransfer(collector, amount);
        
        emit ProtocolFeeCollected(token, amount);
    }
}

