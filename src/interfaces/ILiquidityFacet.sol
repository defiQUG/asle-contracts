// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILiquidityFacet {
    struct Pool {
        address baseToken;
        address quoteToken;
        uint256 baseReserve;
        uint256 quoteReserve;
        uint256 virtualBaseReserve;
        uint256 virtualQuoteReserve;
        uint256 k; // Slippage control coefficient
        uint256 oraclePrice; // Market oracle price (i)
        bool active;
    }

    event PoolCreated(
        uint256 indexed poolId,
        address indexed baseToken,
        address indexed quoteToken
    );

    event LiquidityAdded(
        uint256 indexed poolId,
        address indexed provider,
        uint256 baseAmount,
        uint256 quoteAmount
    );

    event Swap(
        uint256 indexed poolId,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    function createPool(
        address baseToken,
        address quoteToken,
        uint256 initialBaseReserve,
        uint256 initialQuoteReserve,
        uint256 virtualBaseReserve,
        uint256 virtualQuoteReserve,
        uint256 k,
        uint256 oraclePrice
    ) external returns (uint256 poolId);

    function addLiquidity(
        uint256 poolId,
        uint256 baseAmount,
        uint256 quoteAmount
    ) external returns (uint256 lpShares);

    function swap(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function getPool(uint256 poolId) external view returns (Pool memory);

    function getPrice(uint256 poolId) external view returns (uint256);

    function getQuote(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}

