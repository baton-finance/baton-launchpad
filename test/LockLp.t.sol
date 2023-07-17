// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract LockLpTest is Test {
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
                Nft.LockLpParams({amount: 1000, price: 1 ether}),
                Nft.YieldFarmParams({amount: 0, duration: 0})
            )
        );

        // disable the oracle
        oracle.setIsDisabled(address(nft), true);

        // deal some eth to babe
        deal(babe, 100_000 ether);
    }

    function test_sendsLpTokensToNft() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // get the expected lp tokens
        uint256 amountToLock = nft.lockLpParams().amount;
        uint256 expectedLpTokens = pair.addQuote(nft.lockLpParams().price * amountToLock, amountToLock * 1e18, 0);

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(uint32(amountToLock), messages);

        // assert that the lp tokens were sent to the NFT
        assertEq(pair.lpToken().balanceOf(address(nft)), expectedLpTokens);
    }

    function test_createsPairIfItDoesntExist() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(nft.lockLpParams().amount, messages);

        // assert that the pair was created
        assertNotEq(caviar.pairs(address(nft), address(0), bytes32(0)), address(0));
    }

    function test_sendsNftsToPair() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(nft.lockLpParams().amount, messages);

        for (uint256 i = amount; i < amount + nft.lockLpParams().amount; i++) {
            assertEq(nft.ownerOf(i), address(pair));
        }
    }

    function test_RevertIfAmountIsGreaterThanLockedLpParamAmount() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = nft.lockLpParams().amount + 1;
        vm.expectRevert(Nft.InsufficientLpAmount.selector);
        nft.lockLp(amountToLock, messages);
    }

    function test_IncrementsLockedLpSupply() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = 3;
        nft.lockLp(amountToLock, messages);

        // assert that the locked lp supply was incremented
        assertEq(nft.lockedLpSupply(), amountToLock);
    }

    function test_RevertIfLockedLpNotEnabled() public {
        // create the nft
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 3000, merkleRoot: bytes32(0)});
        nft = Nft(
            launchpad.create(
                keccak256(abi.encode(1)),
                "name",
                "symbol",
                categories,
                3000,
                true,
                Nft.VestingParams({receiver: address(0xdead), duration: 0, amount: 0}),
                Nft.LockLpParams({amount: 0, price: 0}),
                Nft.YieldFarmParams({amount: 0, duration: 0})
            )
        );

        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = 10;
        vm.expectRevert(Nft.LockedLpNotEnabled.selector);
        nft.lockLp(amountToLock, messages);
    }

    function test_RevertIfMintNotFinished() public {
        vm.startPrank(babe);

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = 10;
        vm.expectRevert(Nft.MintNotFinished.selector);
        nft.lockLp(amountToLock, messages);
    }

    function test_SetsMintEndTimestamp() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert that the mint end timestamp was set
        assertEq(nft.mintEndTimestamp(), block.timestamp);
    }

    function test_DoesNotSetMintEndTimestampIfNotFullyMinted() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 90;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert that the mint end timestamp was not set
        assertEq(nft.mintEndTimestamp(), 0);
    }

    function test_CannotTransferToPairIfStillLocking() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = 3;
        nft.lockLp(amountToLock, messages);

        // try to transfer nfts to the pair
        vm.expectRevert(Nft.LpStillBeingLocked.selector);
        nft.safeTransferFrom(babe, address(pair), 1);
    }

    function test_CanTransferAfterLockingIsComplete() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = nft.lockLpParams().amount;
        nft.lockLp(amountToLock, messages);

        // try to transfer nfts to the pair
        nft.safeTransferFrom(babe, address(pair), 1);

        // assert that the nft is owned by the pair
        assertEq(nft.ownerOf(1), address(pair));
    }

    function test_RevertIfMinEthRaisedIsTooSmall() public {
        vm.startPrank(babe);

        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        vm.expectRevert(Nft.InsufficientEthRaisedForLockedLp.selector);
        nft = Nft(
            launchpad.create(
                keccak256(abi.encode(2)),
                "name",
                "symbol",
                categories,
                100,
                true,
                Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                Nft.LockLpParams({amount: 101, price: 1 ether}),
                Nft.YieldFarmParams({amount: 0, duration: 0})
            )
        );
    }

    function test_FractionalTokensAreInPool() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 3000;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        pair = caviar.create(address(nft), address(0), bytes32(0));

        // lock the lp
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        uint32 amountToLock = 1000;
        nft.lockLp(amountToLock, messages);

        // assert that the locked lp supply was incremented
        assertEq(pair.balanceOf(address(pair)), 1000e18);
    }
}
