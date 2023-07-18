// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFarm} from "baton-contracts/BatonFarm.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract MigrateTest is Test {
    using stdStorage for StdStorage;

    error TransferCallerNotOwnerNorApproved();
    error OwnerQueryForNonexistentToken();
    error Unauthorized();

    address babe = address(0xbabe);
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
        categories[0] = Nft.Category({price: 1 ether, supply: 3000, merkleRoot: bytes32(0)});
        nft = Nft(
            launchpad.create(
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 3000,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}),
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 100, price: 1 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 1000, duration: 1 days})
                }),
                keccak256(abi.encode(123))
            )
        );

        // disable the oracle
        oracle.setIsDisabled(address(nft), true);

        // deal some eth to babe
        deal(babe, 100_000 ether);
    }

    function test_SetsLockedLpMigrationTarget() public {
        // set the target
        nft.initiateLockedLpMigration(address(0xdead));

        // assert that the target was set
        assertEq(nft.lockedLpMigrationTarget(), address(0xdead));
    }

    function test_RevertIfCallerIsNotOwner() public {
        vm.startPrank(babe);

        // set the target
        vm.expectRevert(Unauthorized.selector);
        nft.initiateLockedLpMigration(address(0xdead));
    }

    function test_MigratesTokensToLockedLpMigrationTarget() public {
        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));
        deal(address(pair.lpToken()), address(nft), 500);

        // initiate the migration
        nft.initiateLockedLpMigration(address(0xdead));

        // execute the migration
        uint256 balanceBefore = pair.lpToken().balanceOf(address(0xdead));
        nft.migrateLockedLp(address(0xdead));

        // assert that the tokens were migrated
        assertEq(pair.lpToken().balanceOf(address(0xdead)), balanceBefore + 500);
    }

    function test_RevertIfMigrationTargetNotMatched() public {
        // initiate the migration
        nft.initiateLockedLpMigration(address(0xdead));

        // execute the migration
        vm.expectRevert(Nft.MigrationTargetNotMatched.selector);
        nft.migrateLockedLp(address(0x123));
    }

    function test_RevertIfMigrationNotInitiated() public {
        // execute the migration
        vm.expectRevert(Nft.MigrationNotInitiated.selector);
        nft.migrateLockedLp(address(0xdead));
    }

    function test_RevertIfCallerToMigrateLockedLpIsNotOwner() public {
        // initiate the migration
        nft.initiateLockedLpMigration(address(0xdead));

        // execute the migration
        vm.startPrank(babe);
        vm.expectRevert(Unauthorized.selector);
        nft.migrateLockedLp(address(0xdead));
    }
}
