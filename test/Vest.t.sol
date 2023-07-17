// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract VestTest is Test {
    using stdStorage for StdStorage;

    error TransferCallerNotOwnerNorApproved();
    error OwnerQueryForNonexistentToken();
    error Unauthorized();

    address babe = address(0xbabe);
    BatonLaunchpad launchpad;
    Nft nftImplementation;
    Caviar caviar;
    BatonFactory batonFactory;
    Nft nft;
    Nft.VestingParams vestingParams;

    function setUp() public {
        // deploy caviar
        StolenNftFilterOracle oracle = new StolenNftFilterOracle();
        caviar = new Caviar(address(oracle));

        // deploy baton factory
        batonFactory = new BatonFactory(payable(address(0)), address(caviar), address(this));

        // deploy the launchpad
        launchpad = new BatonLaunchpad(0);

        // deploy the nft implementation
        nftImplementation = new Nft(address(caviar), address(launchpad), address(batonFactory));

        // set the nft implementation on the launchpad
        launchpad.setNftImplementation(address(nftImplementation));

        // create the nft
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 0.01 ether, supply: 10, merkleRoot: bytes32(0)});
        vestingParams = Nft.VestingParams({receiver: address(babe), duration: 30 days, amount: 300});
        nft = Nft(
            launchpad.create(
                bytes32(0),
                "name",
                "symbol",
                categories,
                10,
                true,
                vestingParams,
                Nft.LockLpParams({amount: 0, price: 0 ether}),
                Nft.YieldFarmParams({amount: 0, duration: 0})
            )
        );

        // deal some eth to babe
        deal(babe, 100 ether);
    }

    function test_MintsToReceiver() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        uint256 babeBalanceBefore = nft.balanceOf(babe);
        skip(1 days);
        nft.vest(10);

        // assert that the NFTs were minted to babe
        assertEq(nft.balanceOf(babe), babeBalanceBefore + 10);
    }

    function test_UpdatesTotalVestClaimed() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        uint256 totalVestClaimedBefore = nft.totalVestClaimed();
        skip(1 days);
        nft.vest(10);

        // assert that the totalVestClaimed was updated
        assertEq(nft.totalVestClaimed(), totalVestClaimedBefore + 10);
    }

    function test_RevertIfInsufficientAmountVested() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        skip(1 days);
        vm.expectRevert(Nft.InsufficientVestedAmount.selector);
        nft.vest(11);
    }

    function test_RevertIfMintNotEnded() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 9;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        skip(1 days);
        vm.expectRevert(Nft.MintNotFinished.selector);
        nft.vest(1);
    }

    function test_RevertIfCallerIsNotReceiver() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 9;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        skip(1 days);
        vm.startPrank(address(0xdead));
        vm.expectRevert(Unauthorized.selector);
        nft.vest(1);
    }

    function test_vested_ReturnsZeroIfMintNotEnded() public {
        assertEq(nft.vested(), 0);
    }

    function test_vested_ReturnsVestedAmount() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        skip(10 days);
        uint256 vested = nft.vested();

        // assert that the vested amount is correct
        assertEq(vested, 100);
    }

    function test_vested_ReturnsMaxIfTimestampIsPastVestingEndTimestamp() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // claim the vested NFTs
        skip(100 days);
        uint256 vested = nft.vested();

        // assert that the vested amount is correct
        assertEq(vested, 300);
    }

    function test_mint_setsMintEndTimestampIfMintIsComplete() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 10;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert that the mint end timestamp is set
        assertEq(nft.mintEndTimestamp(), block.timestamp);
    }

    function test_mint_doesNotSetMintEndTimestampIfNotComplete() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 9;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert that the mint end timestamp is not set
        assertEq(nft.mintEndTimestamp(), 0);
    }
}
