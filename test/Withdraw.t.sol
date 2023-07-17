// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFarm} from "baton-contracts/BatonFarm.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract WithdrawTest is Test {
    using stdStorage for StdStorage;

    error TransferCallerNotOwnerNorApproved();
    error OwnerQueryForNonexistentToken();
    error Unauthorized();

    address babe = address(0xbabe);
    address owner = address(0xcafe);
    BatonLaunchpad launchpad;
    Nft nftImplementation;
    Nft nft;
    Caviar caviar;
    Pair pair;
    BatonFactory batonFactory;

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

        launchpad.setNftImplementation(address(nftImplementation));

        // create the nft
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 0.3 ether, supply: 3000, merkleRoot: bytes32(0)});
        vm.prank(owner);
        nft = Nft(
            launchpad.create(
                bytes32(0),
                "name",
                "symbol",
                categories,
                3000,
                true,
                Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                Nft.LockLpParams({amount: 100, price: 1 ether}),
                Nft.YieldFarmParams({amount: 1000, duration: 1 days})
            )
        );

        // disable the oracle
        oracle.setIsDisabled(address(nft), true);

        // deal some eth to babe
        deal(babe, 100_000 ether);
    }

    function test_TransfersEthToOwner() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // lock lp and seed yield farm
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(100, messages);
        nft.seedYieldFarm(1000, messages);

        // withdraw
        vm.startPrank(owner);
        nft.withdraw();

        // assert that the eth was sent to the owner
        uint256 expectedEth = 0.3 ether * 3000 - 100 * 1 ether;
        assertEq(owner.balance, expectedEth);
    }

    function test_RevertIfYieldFarmStillBeingSeeded() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // lock lp and seed yield farm
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(100, messages);
        nft.seedYieldFarm(999, messages);

        // try to withdraw
        vm.startPrank(owner);
        vm.expectRevert(Nft.YieldFarmStillBeingSeeded.selector);
        nft.withdraw();
    }

    function test_RevertIfLpStillBeingLocked() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // lock lp and seed yield farm
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(99, messages);

        // try to withdraw
        vm.startPrank(owner);
        vm.expectRevert(Nft.LpStillBeingLocked.selector);
        nft.withdraw();
    }

    function test_RevertIfMintNotFinished() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 2999;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // try to withdraw
        vm.startPrank(owner);
        vm.expectRevert(Nft.MintNotFinished.selector);
        nft.withdraw();
    }

    function test_RevertIfCallerNotOwner() public {
        // try to withdraw
        vm.startPrank(babe);
        vm.expectRevert(Unauthorized.selector);
        nft.withdraw();
    }
}
