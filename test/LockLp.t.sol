// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract LockLpTest is Test {
    using stdStorage for StdStorage;

    error TransferCallerNotOwnerNorApproved();
    error OwnerQueryForNonexistentToken();

    address babe = address(0xbabe);
    BatonLaunchpad launchpad;
    Nft nftImplementation;
    Nft nft;

    function setUp() public {
        // deploy the nft implementation
        nftImplementation = new Nft();

        // deploy the launchpad
        launchpad = new BatonLaunchpad(address(nftImplementation));

        // create the nft
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        nft = Nft(
            launchpad.create(
                bytes32(0),
                "name",
                "symbol",
                categories,
                100,
                true,
                Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                Nft.LockLpParams({amount: 100, price: 1 ether})
            )
        );

        // deal some eth to babe
        deal(babe, 100 ether);
    }
}
