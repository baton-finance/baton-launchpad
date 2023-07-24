// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import "../src/BatonLaunchpad.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract RefundTest is Test {
    using stdStorage for StdStorage;

    error OwnerQueryForNonexistentToken();
    error TransferCallerNotOwnerNorApproved();

    address babe = address(0xbabe);
    BatonLaunchpad launchpad;
    Nft nftImplementation;
    Caviar caviar;
    BatonFactory batonFactory;
    Nft nft;
    uint64 mintEndTimestamp;

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
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        mintEndTimestamp = uint64(block.timestamp + 1 days);
        // create the nft
        nft = Nft(
            launchpad.create(
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 100,
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: mintEndTimestamp}),
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 0, price: 0 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
                }),
                bytes32(0)
            )
        );

        // deal some eth to babe
        deal(babe, 100 ether);
    }

    function test_SendsEthToCaller() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // get the balance of babe
        uint256 balanceBefore = babe.balance;

        // send the nft to the launchpad
        vm.warp(mintEndTimestamp + 1);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        nft.refund(tokenIds);

        // assert that the balance of babe has increased
        assertEq(babe.balance - balanceBefore, nft.categories(0).price * tokenIds.length);
    }

    function test_UpdatesAccount() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // send the nft to the launchpad
        vm.warp(mintEndTimestamp + 1);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        nft.refund(tokenIds);

        // assert the total minted has decreased and available refund has decreased
        assertEq(nft.accounts(babe).totalMinted, amount - tokenIds.length);
        assertEq(
            nft.accounts(babe).availableRefund,
            amount * nft.categories(0).price - tokenIds.length * nft.categories(0).price
        );
    }

    function test_BurnsNftFromCaller() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // send the nft to the launchpad
        vm.warp(mintEndTimestamp + 1);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        nft.refund(tokenIds);

        // assert that the nft has been burned
        assertEq(nft.balanceOf(babe), amount - tokenIds.length);
        assertEq(nft.totalSupply(), amount - tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.expectRevert(OwnerQueryForNonexistentToken.selector);
            nft.ownerOf(tokenIds[i]);
        }
    }

    function test_RevertIfCallerDoesNotOwnToken() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // send the nft to the launchpad
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        vm.warp(mintEndTimestamp + 1);

        vm.startPrank(address(0xdead));
        vm.expectRevert(TransferCallerNotOwnerNorApproved.selector);
        nft.refund(tokenIds);
    }

    function test_MultiRefundSendsCorrectEthToCaller() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));
        vm.warp(mintEndTimestamp + 1);

        for (uint256 i = 0; i < amount; i++) {
            // get the balance of babe
            uint256 balanceBefore = babe.balance;

            // send the nft to the launchpad
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = i;
            nft.refund(tokenIds);

            // assert that the balance of babe has increased
            assertEq(babe.balance - balanceBefore, nft.categories(0).price);
        }

        // assert the total minted is zero and available refund is zero
        assertEq(nft.accounts(babe).totalMinted, 0);
        assertEq(nft.accounts(babe).availableRefund, 0);
    }

    function test_RevertIfRefundsNotEnabled() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});

        // create the nft
        nft = Nft(
            launchpad.create(
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 100,
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}), // disable refunds
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 0, price: 0 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
                }),
                keccak256(abi.encode(123))
            )
        );

        vm.expectRevert(Nft.RefundsNotEnabled.selector);
        nft.refund(new uint256[](0));
    }

    function test_UpdatesAccountOnMint() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert the total minted has increased and available refund has increased
        assertEq(nft.accounts(babe).totalMinted, amount);
        assertEq(nft.accounts(babe).availableRefund, amount * nft.categories(0).price);
    }

    function test_SkipsAccountUpdateIfRefundsNotEnabled() public {
        vm.startPrank(babe);

        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});

        // create the nft
        nft = Nft(
            launchpad.create(
                BatonLaunchpad.CreateParams({
                    name: "name",
                    symbol: "symbol",
                    categories: categories,
                    maxMintSupply: 100,
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 0}), // disable refunds
                    vestingParams: Nft.VestingParams({receiver: address(0), duration: 0, amount: 0}),
                    lockLpParams: Nft.LockLpParams({amount: 0, price: 0 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
                }),
                keccak256(abi.encode(123))
            )
        );

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert the total minted and available refund were not updated
        assertEq(nft.accounts(babe).totalMinted, 0);
        assertEq(nft.accounts(babe).availableRefund, 0);
    }

    function test_RevertIfMintComplete() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = nft.maxMintSupply();
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // send the nft to the launchpad
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        vm.warp(mintEndTimestamp + 1);

        vm.expectRevert(Nft.MintComplete.selector);
        nft.refund(tokenIds);
    }

    function test_RevertIfMintNotExpired() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // send the nft to the launchpad
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        vm.warp(mintEndTimestamp - 1);

        vm.expectRevert(Nft.MintNotExpired.selector);
        nft.refund(tokenIds);
    }
}
