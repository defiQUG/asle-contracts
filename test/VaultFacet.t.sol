// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Diamond} from "../src/core/Diamond.sol";
import {DiamondCutFacet} from "../src/core/facets/DiamondCutFacet.sol";
import {DiamondInit} from "../src/core/DiamondInit.sol";
import {VaultFacet} from "../src/core/facets/VaultFacet.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IVaultFacet} from "../src/interfaces/IVaultFacet.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract VaultFacetTest is Test {
    Diamond public diamond;
    DiamondCutFacet public diamondCutFacet;
    DiamondInit public diamondInit;
    VaultFacet public vaultFacet;
    ERC20Mock public asset;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy mock ERC20
        asset = new ERC20Mock("Test Asset", "TA", 18);

        // Deploy facets
        diamondCutFacet = new DiamondCutFacet();
        vaultFacet = new VaultFacet();
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

        // Add VaultFacet
        bytes4[] memory vaultSelectors = new bytes4[](5);
        vaultSelectors[0] = IVaultFacet.createVault.selector;
        vaultSelectors[1] = IVaultFacet.getVault.selector;
        vaultSelectors[2] = IVaultFacet.deposit.selector;
        vaultSelectors[3] = IVaultFacet.convertToShares.selector;
        vaultSelectors[4] = IVaultFacet.convertToAssets.selector;
        
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(vaultFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: vaultSelectors
        });

        // Initialize
        bytes memory initData = abi.encodeWithSelector(DiamondInit.init.selector, owner);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(diamondInit), initData);
    }

    function testCreateVault() public {
        uint256 vaultId = IVaultFacet(address(diamond)).createVault(address(asset), false);
        assertEq(vaultId, 0, "First vault should have ID 0");

        IVaultFacet.Vault memory vault = IVaultFacet(address(diamond)).getVault(vaultId);
        assertEq(vault.asset, address(asset));
        assertFalse(vault.isMultiAsset);
        assertTrue(vault.active);
    }

    function testCreateMultiAssetVault() public {
        uint256 vaultId = IVaultFacet(address(diamond)).createVault(address(0), true);
        
        IVaultFacet.Vault memory vault = IVaultFacet(address(diamond)).getVault(vaultId);
        assertTrue(vault.isMultiAsset);
        assertTrue(vault.active);
    }

    function testConvertToShares() public {
        uint256 vaultId = IVaultFacet(address(diamond)).createVault(address(asset), false);
        
        // First deposit - should be 1:1
        uint256 assets = 1000 ether;
        uint256 shares = IVaultFacet(address(diamond)).convertToShares(vaultId, assets);
        assertEq(shares, assets, "First deposit should be 1:1");
    }

    function testConvertToAssets() public {
        uint256 vaultId = IVaultFacet(address(diamond)).createVault(address(asset), false);
        
        uint256 shares = 1000 ether;
        uint256 assets = IVaultFacet(address(diamond)).convertToAssets(vaultId, shares);
        // Empty vault should return 0
        assertEq(assets, 0);
    }
}

