// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFarm} from "baton-contracts/BatonFarm.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract SeedYieldFarmTest is Test {
    using stdStorage for StdStorage;

    error TransferCallerNotOwnerNorApproved();
    error OwnerQueryForNonexistentToken();

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
                bytes32(0),
                "name",
                "symbol",
                categories,
                3000,
                true,
                Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                Nft.LockLpParams({amount: 0, price: 0}),
                Nft.YieldFarmParams({amount: 1000, duration: 1 days})
            )
        );

        // disable the oracle
        oracle.setIsDisabled(address(nft), true);

        // deal some eth to babe
        deal(babe, 100_000 ether);
    }
}
