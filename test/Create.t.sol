// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract CreateTest is Test {
// BatonLaunchpad launchpad;
// Nft nftImplementation;

// function setUp() public {
//     // deploy the nft implementation
//     nftImplementation = new Nft();

//     // deploy the launchpad
//     launchpad = new BatonLaunchpad(address(nftImplementation));
// }

// function test_InitializesNft() public {
//     // set the categories
//     Nft.Category[] memory categories = new Nft.Category[](2);
//     categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
//     categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

//     // create the nft
//     Nft nft = Nft(
//         launchpad.create(
//             bytes32(0),
//             "name",
//             "symbol",
//             categories,
//             false,
//             Nft.VestingParams({receiver: address(0), duration: 0, amount: 0})
//         )
//     );

//     // check that the name is correct
//     assertEq(nft.name(), "name");

//     // check that the symbol is correct
//     assertEq(nft.symbol(), "symbol");

//     // check that the categories are correct
//     assertEq(nft.categories(0).price, 1 ether);
//     assertEq(nft.categories(0).supply, 100);
//     assertEq(nft.categories(1).price, 2 ether);
//     assertEq(nft.categories(1).supply, 200);
// }

// function test_RevertIfTooManyCategories() public {
//     // set the categories
//     Nft.Category[] memory categories = new Nft.Category[](257);

//     // check that it reverts
//     vm.expectRevert(Nft.TooManyCategories.selector);
//     launchpad.create(
//         bytes32(0),
//         "name",
//         "symbol",
//         categories,
//         false,
//         Nft.VestingParams({receiver: address(0), duration: 0, amount: 0})
//     );
// }
}
