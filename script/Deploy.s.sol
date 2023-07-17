// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/BatonLaunchpad.sol";
import "../src/Nft.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // deploy the launchpad
        uint256 feeRate = 0;
        BatonLaunchpad launchpad = new BatonLaunchpad(feeRate);

        console.log("launchpad:", address(launchpad));

        // deploy the nft implementation
        Nft nftImplementation =
            new Nft(vm.envAddress("CAVIAR_ADDRESS"), address(launchpad), vm.envAddress("BATON_FACTORY_ADDRESS"));

        console.log("nft implementation:", address(nftImplementation));

        // set the nft implementation on the launchpad
        launchpad.setNftImplementation(address(nftImplementation));

        vm.stopBroadcast();
    }
}
