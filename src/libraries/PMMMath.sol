// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library PMMMath {
    /**
     * @dev Calculate price using DODO PMM formula
     * @param i Oracle price
     * @param k Slippage control coefficient (0-1, typically 0.1-0.3)
     * @param Q Current quote token reserve
     * @param vQ Virtual quote token reserve
     * @return price Calculated price
     */
    function calculatePrice(
        uint256 i,
        uint256 k,
        uint256 Q,
        uint256 vQ
    ) internal pure returns (uint256 price) {
        require(vQ > 0, "PMMMath: vQ must be > 0");
        require(k <= 1e18, "PMMMath: k must be <= 1");
        
        // p = i * (1 + k * (Q - vQ) / vQ)
        // Using fixed-point arithmetic with 1e18 precision
        uint256 priceAdjustment = (Q > vQ) 
            ? (k * (Q - vQ) * 1e18) / vQ
            : (k * (vQ - Q) * 1e18) / vQ;
        
        if (Q > vQ) {
            price = (i * (1e18 + priceAdjustment)) / 1e18;
        } else {
            price = (i * (1e18 - priceAdjustment)) / 1e18;
        }
    }

    /**
     * @dev Calculate output amount for a swap using DODO PMM formula
     * PMM Formula: R = i - (i * k * (B - B0) / B0)
     * Where: i = oracle price, k = slippage coefficient, B = current balance, B0 = target balance
     * @param amountIn Input amount
     * @param reserveIn Input token reserve
     * @param reserveOut Output token reserve
     * @param virtualReserveIn Virtual input reserve (target balance)
     * @param virtualReserveOut Virtual output reserve (target balance)
     * @param k Slippage coefficient (0-1e18, typically 0.1e18-0.3e18)
     * @param oraclePrice Oracle price (i) - price of quote/base in 1e18 precision
     * @return amountOut Output amount
     */
    function calculateSwapOutput(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 virtualReserveIn,
        uint256 virtualReserveOut,
        uint256 k,
        uint256 oraclePrice
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "PMMMath: amountIn must be > 0");
        require(virtualReserveIn > 0 && virtualReserveOut > 0, "PMMMath: virtual reserves must be > 0");
        require(k <= 1e18, "PMMMath: k must be <= 1");
        require(oraclePrice > 0, "PMMMath: oraclePrice must be > 0");
        
        // Use virtual reserves for PMM calculation
        uint256 newReserveIn = reserveIn + amountIn;
        
        // Calculate new price after input
        // Price formula: P = i * (1 + k * (Q - Q0) / Q0)
        // Where Q is current quote reserve, Q0 is virtual quote reserve
        // For base token: we calculate how much quote we get
        
        // Calculate effective reserves (use virtual if larger)
        uint256 effectiveBase = virtualReserveIn > reserveIn ? virtualReserveIn : reserveIn;
        uint256 effectiveQuote = virtualReserveOut > reserveOut ? virtualReserveOut : reserveOut;
        
        // DODO PMM: when buying quote with base
        // New quote reserve = Q0 - (i * (B1 - B0) / (1 + k * (B1 - B0) / B0))
        // Simplified: use constant product with virtual reserves adjusted by k
        
        // Calculate price impact using PMM curve
        // The curve ensures that as reserves move away from target, price adjusts
        uint256 baseDiff = newReserveIn > virtualReserveIn 
            ? newReserveIn - virtualReserveIn 
            : virtualReserveIn - newReserveIn;
        
        // Calculate price adjustment factor
        uint256 priceAdjustment = (baseDiff * k) / virtualReserveIn;
        
        // Calculate output using PMM formula
        // AmountOut = (amountIn * oraclePrice) / (1 + k * deviation)
        uint256 baseAmountIn = newReserveIn - reserveIn;
        
        // Convert to quote using oracle price with slippage
        uint256 quoteValue = (baseAmountIn * oraclePrice) / 1e18;
        
        // Apply PMM curve: reduce output as reserves deviate from target
        if (newReserveIn > virtualReserveIn) {
            // Price goes up (sell premium)
            uint256 adjustedPrice = (oraclePrice * (1e18 + priceAdjustment)) / 1e18;
            quoteValue = (baseAmountIn * adjustedPrice) / 1e18;
        } else {
            // Price goes down (buy discount)
            uint256 adjustedPrice = (oraclePrice * (1e18 - priceAdjustment)) / 1e18;
            quoteValue = (baseAmountIn * adjustedPrice) / 1e18;
        }
        
        // Ensure output doesn't exceed available reserves
        amountOut = quoteValue < reserveOut ? quoteValue : reserveOut;
        
        // Apply constant product as fallback for edge cases
        if (amountOut == 0 || amountOut >= reserveOut) {
            uint256 constantProduct = effectiveBase * effectiveQuote;
            uint256 newEffectiveBase = effectiveBase + amountIn;
            uint256 newEffectiveQuote = constantProduct / newEffectiveBase;
            amountOut = effectiveQuote > newEffectiveQuote ? effectiveQuote - newEffectiveQuote : 0;
        }
        
        require(amountOut > 0, "PMMMath: insufficient liquidity");
        require(amountOut <= reserveOut, "PMMMath: output exceeds reserves");
    }

    /**
     * @dev Calculate LP shares for liquidity addition
     * @param baseAmount Base token amount
     * @param quoteAmount Quote token amount
     * @param totalBaseReserve Total base reserve
     * @param totalQuoteReserve Total quote reserve
     * @param totalSupply Current total LP supply
     * @return shares LP shares to mint
     */
    function calculateLPShares(
        uint256 baseAmount,
        uint256 quoteAmount,
        uint256 totalBaseReserve,
        uint256 totalQuoteReserve,
        uint256 totalSupply
    ) internal pure returns (uint256 shares) {
        if (totalSupply == 0) {
            // First liquidity provider
            shares = sqrt(baseAmount * quoteAmount);
        } else {
            // Calculate shares proportionally
            uint256 baseShares = (baseAmount * totalSupply) / totalBaseReserve;
            uint256 quoteShares = (quoteAmount * totalSupply) / totalQuoteReserve;
            shares = baseShares < quoteShares ? baseShares : quoteShares;
        }
    }

    /**
     * @dev Calculate square root using Babylonian method
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}

