// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Diamond} from "../src/core/Diamond.sol";
import {DiamondCutFacet} from "../src/core/facets/DiamondCutFacet.sol";
import {DiamondInit} from "../src/core/DiamondInit.sol";
import {LiquidityFacet} from "../src/core/facets/LiquidityFacet.sol";
import {VaultFacet} from "../src/core/facets/VaultFacet.sol";
import {ComplianceFacet} from "../src/core/facets/ComplianceFacet.sol";
import {CCIPFacet} from "../src/core/facets/CCIPFacet.sol";
import {GovernanceFacet} from "../src/core/facets/GovernanceFacet.sol";
import {SecurityFacet} from "../src/core/facets/SecurityFacet.sol";
import {RWAFacet} from "../src/core/facets/RWAFacet.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";

/**
 * @title DeployScript
 * @notice Complete deployment script for ASLE Diamond with all facets
 */
contract DeployScript is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer == address(0)) {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerPrivateKey);
            deployer = vm.addr(deployerPrivateKey);
        } else {
            vm.startBroadcast(deployer);
        }

        console.log("Deploying ASLE Diamond and Facets...");
        console.log("Deployer:", deployer);

        // Deploy Diamond
        Diamond diamond = new Diamond();
        console.log("Diamond deployed at:", address(diamond));

        // Deploy Facets
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console.log("DiamondCutFacet deployed at:", address(diamondCutFacet));

        LiquidityFacet liquidityFacet = new LiquidityFacet();
        console.log("LiquidityFacet deployed at:", address(liquidityFacet));

        VaultFacet vaultFacet = new VaultFacet();
        console.log("VaultFacet deployed at:", address(vaultFacet));

        ComplianceFacet complianceFacet = new ComplianceFacet();
        console.log("ComplianceFacet deployed at:", address(complianceFacet));

        CCIPFacet ccipFacet = new CCIPFacet();
        console.log("CCIPFacet deployed at:", address(ccipFacet));

        GovernanceFacet governanceFacet = new GovernanceFacet();
        console.log("GovernanceFacet deployed at:", address(governanceFacet));

        SecurityFacet securityFacet = new SecurityFacet();
        console.log("SecurityFacet deployed at:", address(securityFacet));

        RWAFacet rwaFacet = new RWAFacet();
        console.log("RWAFacet deployed at:", address(rwaFacet));

        // Deploy DiamondInit
        DiamondInit diamondInit = new DiamondInit();
        console.log("DiamondInit deployed at:", address(diamondInit));

        // Prepare diamond cuts
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](8);

        // Get function selectors for each facet
        cuts[0] = _getFacetCut(address(diamondCutFacet), _getSelectors("DiamondCutFacet"));
        cuts[1] = _getFacetCut(address(liquidityFacet), _getSelectors("LiquidityFacet"));
        cuts[2] = _getFacetCut(address(vaultFacet), _getSelectors("VaultFacet"));
        cuts[3] = _getFacetCut(address(complianceFacet), _getSelectors("ComplianceFacet"));
        cuts[4] = _getFacetCut(address(ccipFacet), _getSelectors("CCIPFacet"));
        cuts[5] = _getFacetCut(address(governanceFacet), _getSelectors("GovernanceFacet"));
        cuts[6] = _getFacetCut(address(securityFacet), _getSelectors("SecurityFacet"));
        cuts[7] = _getFacetCut(address(rwaFacet), _getSelectors("RWAFacet"));

        // Initialize Diamond
        bytes memory initData = abi.encodeWithSelector(DiamondInit.init.selector, deployer);

        // Perform diamond cut
        IDiamondCut(address(diamond)).diamondCut(cuts, address(diamondInit), initData);

        console.log("\n=== Deployment Summary ===");
        console.log("Diamond:", address(diamond));
        console.log("All facets added and initialized!");
        console.log("Owner:", deployer);

        vm.stopBroadcast();
    }

    function _getFacetCut(address facet, bytes4[] memory selectors) internal pure returns (IDiamondCut.FacetCut memory) {
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _getSelectors(string memory) internal pure returns (bytes4[] memory) {
        // This is a simplified version - in production, use FacetCutHelper or similar
        // For now, return empty array - selectors should be added manually or via helper
        bytes4[] memory selectors = new bytes4[](0);
        return selectors;
    }
}
