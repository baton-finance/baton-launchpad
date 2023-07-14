// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract RefundTest is Test {
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
                true,
                Nft.VestingParams({receiver: address(0), duration: 0, amount: 0})
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

        vm.startPrank(address(0xdead));
        vm.expectRevert(TransferCallerNotOwnerNorApproved.selector);
        nft.refund(tokenIds);
    }

    function test_MultiRefundSendsCorrectEthToCaller() public {
        vm.startPrank(babe);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

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
        // disable refunds
        stdstore.target(address(nft)).sig("refunds()").checked_write(false);

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

        // disable refunds
        stdstore.target(address(nft)).sig("refunds()").checked_write(false);

        // mint the nft
        uint256 amount = 5;
        nft.mint{value: amount * nft.categories(0).price}(uint64(amount), 0, new bytes32[](0));

        // assert the total minted and available refund were not updated
        assertEq(nft.accounts(babe).totalMinted, 0);
        assertEq(nft.accounts(babe).availableRefund, 0);
    }
}
