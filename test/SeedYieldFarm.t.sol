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
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 3000,
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}),
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 0, price: 0 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 1000, duration: 1 days})
                }),
                bytes32(0)
            )
        );

        // disable the oracle
        oracle.setIsDisabled(address(nft), true);

        // deal some eth to babe
        deal(babe, 100_000 ether);
    }

    function test_ApprovesYieldFarmToTransferTokens() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // assert that the yield farm is approved to spend tokens
        assertEq(pair.allowance(address(nft), address(nft.yieldFarm())), type(uint256).max);
    }

    function test_YieldFarmIsCreated() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // assert the yield farm was created
        assertNotEq(address(nft.yieldFarm()), address(0));

        // assert that the fractional reward tokens were sent to the yield farm
        assertApproxEqAbs(pair.balanceOf(address(nft.yieldFarm())), amountToLock * 1e18, 100_000);
    }

    function test_NftsWereMinted() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // assert that the nfts were minted
        for (uint256 i = amount; i < amount + amountToLock; i++) {
            assertEq(nft.ownerOf(uint256(i)), address(pair));
        }
    }

    function test_CreatesCaviarPairIfItDoesntExist() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // create the caviar pair
        pair = Pair(caviar.pairs(address(nft), address(0), bytes32(0)));

        // assert that the caviar pair was created
        assertNotEq(address(pair), address(0));
    }

    function test_RevertIfThereArentEnoughNftsToSeedTheYieldFarm() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // seed the yield farm
        uint256 amountToLock = nft.yieldFarmParams().amount + 1;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        vm.expectRevert(Nft.InsufficientYieldFarmAmount.selector);
        nft.seedYieldFarm(uint32(amountToLock), messages);
    }

    function test_IncrementsSeededYieldFarmSupply() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // assert that the seeded yield farm supply was incremented
        assertEq(nft.seededYieldFarmSupply(), amountToLock);
    }

    function test_RevertIfYieldFarmIsNotEnabled() public {
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
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}),
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 0, price: 0 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
                }),
                keccak256(abi.encode(123))
            )
        );

        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        vm.expectRevert(Nft.YieldFarmNotEnabled.selector);
        nft.seedYieldFarm(uint32(amountToLock), messages);
    }

    function test_RevertIfLockedLpIsStillLocking() public {
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
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}),
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 100, price: 1 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 100, duration: 1 days})
                }),
                keccak256(abi.encode(123))
            )
        );

        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        vm.expectRevert(Nft.LpStillBeingLocked.selector);
        nft.seedYieldFarm(uint32(amountToLock), messages);
    }

    function test_RevertIfMintHasNotFinished() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 100;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        vm.expectRevert(Nft.MintNotComplete.selector);
        nft.seedYieldFarm(uint32(amountToLock), messages);
    }

    function test_AddsAdditionalRewardsOnSecondCall() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // create the caviar pair
        pair = caviar.create(address(nft), address(0), bytes32(0));

        // seed the yield farm with just 100 nfts
        uint256 amountToLock = 100;
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(uint32(amountToLock), messages);

        uint256 balanceBefore = pair.balanceOf(address(nft.yieldFarm()));

        // seed the yield farm with another 100 nfts
        nft.seedYieldFarm(uint32(amountToLock), messages);

        // assert that the additional rewards were added
        assertApproxEqAbs(pair.balanceOf(address(nft.yieldFarm())), balanceBefore + amountToLock * 1e18, 100_000);
    }
}
