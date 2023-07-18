// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract CreateTest is Test {
    BatonLaunchpad launchpad;
    Nft nftImplementation;

    function setUp() public {
        // deploy the launchpad
        launchpad = new BatonLaunchpad(0);

        // deploy the nft implementation
        nftImplementation = new Nft(address(0), address(launchpad), address(0));

        launchpad.setNftImplementation(address(nftImplementation));
    }

    function test_InitializesNft() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // create the nft
        Nft nft = Nft(
            launchpad.create(
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 3000,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                    vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                    lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 45, duration: 100 days})
                }),
                keccak256(abi.encode(88))
            )
        );

        // check that the name is correct
        assertEq(nft.name(), "name");

        // check that the symbol is correct
        assertEq(nft.symbol(), "symbol");

        // check that the categories are correct
        assertEq(nft.categories(0).price, 1 ether);
        assertEq(nft.categories(0).supply, 100);
        assertEq(nft.categories(1).price, 2 ether);
        assertEq(nft.categories(1).supply, 200);

        // check that the max mint supply was set
        assertEq(nft.maxMintSupply(), 3000);

        // check that the refunds flag was set
        assertEq(nft.refundParams().mintEndTimestamp, 500);

        // check that the vesting params were set
        assertEq(nft.vestingParams().receiver, address(0x123));
        assertEq(nft.vestingParams().duration, 5 days);
        assertEq(nft.vestingParams().amount, 5);

        // check that the lock lp params were set
        assertEq(nft.lockLpParams().amount, 50);
        assertEq(nft.lockLpParams().price, 1 ether);

        // check that the yield farm params were set
        assertEq(nft.yieldFarmParams().amount, 45);
        assertEq(nft.yieldFarmParams().duration, 100 days);

        // check that the owner was set
        assertEq(nft.owner(), address(this));
    }

    function test_RevertIfTooManyCategories() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](257);

        // check that it reverts
        vm.expectRevert(Nft.TooManyCategories.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 45, duration: 100 days})
            }),
            keccak256(abi.encode(88))
        );
    }
}
