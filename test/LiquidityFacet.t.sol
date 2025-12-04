// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Diamond} from "../src/core/Diamond.sol";
import {DiamondCutFacet} from "../src/core/facets/DiamondCutFacet.sol";
import {DiamondInit} from "../src/core/DiamondInit.sol";
import {LiquidityFacet} from "../src/core/facets/LiquidityFacet.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {ILiquidityFacet} from "../src/interfaces/ILiquidityFacet.sol";

contract LiquidityFacetTest is Test {
    Diamond public diamond;
    DiamondCutFacet public diamondCutFacet;
    DiamondInit public diamondInit;
    LiquidityFacet public liquidityFacet;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy facets
        diamondCutFacet = new DiamondCutFacet();
        liquidityFacet = new LiquidityFacet();
        diamondInit = new DiamondInit();

        // Deploy diamond
        diamond = new Diamond();

        // Prepare cuts
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);

        // Add DiamondCutFacet
        bytes4[] memory diamondCutSelectors = new bytes4[](1);
        diamondCutSelectors[0] = IDiamondCut.diamondCut.selector;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondCutSelectors
        });

        // Add LiquidityFacet (simplified selector list)
        bytes4[] memory liquiditySelectors = new bytes4[](6);
        liquiditySelectors[0] = ILiquidityFacet.createPool.selector;
        liquiditySelectors[1] = ILiquidityFacet.getPool.selector;
        liquiditySelectors[2] = ILiquidityFacet.getPrice.selector;
        liquiditySelectors[3] = ILiquidityFacet.addLiquidity.selector;
        liquiditySelectors[4] = ILiquidityFacet.swap.selector;
        liquiditySelectors[5] = ILiquidityFacet.getQuote.selector;
        
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(liquidityFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: liquiditySelectors
        });

        // Initialize
        bytes memory initData = abi.encodeWithSelector(DiamondInit.init.selector, owner);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(diamondInit), initData);
    }

    function testCreatePool() public {
        address baseToken = address(0x100);
        address quoteToken = address(0x200);
        uint256 initialBaseReserve = 1000 ether;
        uint256 initialQuoteReserve = 2000 ether;
        uint256 virtualBaseReserve = 5000 ether;
        uint256 virtualQuoteReserve = 10000 ether;
        uint256 k = 5000; // 50% in basis points
        uint256 oraclePrice = 2 ether;

        uint256 poolId = ILiquidityFacet(address(diamond)).createPool(
            baseToken,
            quoteToken,
            initialBaseReserve,
            initialQuoteReserve,
            virtualBaseReserve,
            virtualQuoteReserve,
            k,
            oraclePrice,
            address(0) // No oracle for now
        );

        assertEq(poolId, 0, "First pool should have ID 0");

        ILiquidityFacet.Pool memory pool = ILiquidityFacet(address(diamond)).getPool(poolId);
        assertEq(pool.baseToken, baseToken);
        assertEq(pool.quoteToken, quoteToken);
        assertEq(pool.baseReserve, initialBaseReserve);
        assertEq(pool.quoteReserve, initialQuoteReserve);
        assertTrue(pool.active, "Pool should be active");
    }

    function testGetPrice() public {
        // Create pool first
        address baseToken = address(0x100);
        address quoteToken = address(0x200);
        uint256 poolId = ILiquidityFacet(address(diamond)).createPool(
            baseToken,
            quoteToken,
            1000 ether,
            2000 ether,
            5000 ether,
            10000 ether,
            5000,
            2 ether,
            address(0)
        );

        uint256 price = ILiquidityFacet(address(diamond)).getPrice(poolId);
        assertGt(price, 0, "Price should be greater than 0");
    }

    function testMultiplePools() public {
        address baseToken1 = address(0x100);
        address quoteToken1 = address(0x200);
        
        uint256 poolId1 = ILiquidityFacet(address(diamond)).createPool(
            baseToken1,
            quoteToken1,
            1000 ether,
            2000 ether,
            5000 ether,
            10000 ether,
            5000,
            2 ether,
            address(0)
        );

        uint256 poolId2 = ILiquidityFacet(address(diamond)).createPool(
            address(0x300),
            address(0x400),
            500 ether,
            1000 ether,
            2500 ether,
            5000 ether,
            5000,
            2 ether,
            address(0)
        );

        assertEq(poolId1, 0);
        assertEq(poolId2, 1);

        ILiquidityFacet.Pool memory pool1 = ILiquidityFacet(address(diamond)).getPool(poolId1);
        ILiquidityFacet.Pool memory pool2 = ILiquidityFacet(address(diamond)).getPool(poolId2);

        assertEq(pool1.baseToken, baseToken1);
        assertEq(pool2.baseToken, address(0x300));
    }
}
