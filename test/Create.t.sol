// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract CreateTest is Test {
    BatonLaunchpad launchpad;
    Nft nftImplementation;

    error Unauthorized();

    receive() external payable {}

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
                    maxMintSupply: 199,
                    royaltyRate: 100, // 1%
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
        assertEq(nft.maxMintSupply(), 199);

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

        // check the royalty rate
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 100_000);
        assertEq(royaltyAmount, 1000);
        assertEq(receiver, address(this));
    }

    function test_CreatesWithZeroRoyalty() public {
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
                    maxMintSupply: 100,
                    royaltyRate: 0,
                    refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                    vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                    lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                    yieldFarmParams: Nft.YieldFarmParams({amount: 45, duration: 100 days})
                }),
                keccak256(abi.encode(88))
            )
        );

        // check the royalty rate
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 100_000);
        assertEq(royaltyAmount, 0);
        assertEq(receiver, address(this));
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
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 45, duration: 100 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_RevertIfMaxMintSupplyIsGreaterThanCategoriesSupply() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // check that it reverts
        vm.expectRevert(Nft.MaxMintSupplyTooLarge.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 301,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 45, duration: 100 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_RevertIf_InvalidYieldFarmParams() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // check that it reverts
        vm.expectRevert(Nft.InvalidYieldFarmParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 1 days})
            }),
            keccak256(abi.encode(88))
        );

        // check that it reverts
        vm.expectRevert(Nft.InvalidYieldFarmParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 50, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 100, duration: 0 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_RevertIf_InvalidLockLpParams() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // check that it reverts
        vm.expectRevert(Nft.InvalidLockLpParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 0, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
            }),
            keccak256(abi.encode(88))
        );

        // check that it reverts
        vm.expectRevert(Nft.InvalidLockLpParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 100, price: 0}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_RevertIf_InvalidVestingParams() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // check that it reverts
        vm.expectRevert(Nft.InvalidVestingParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0), duration: 5 days, amount: 5}),
                lockLpParams: Nft.LockLpParams({amount: 0, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0})
            }),
            keccak256(abi.encode(88))
        );

        // check that it reverts
        vm.expectRevert(Nft.InvalidVestingParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 0}),
                lockLpParams: Nft.LockLpParams({amount: 100, price: 0}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0 days})
            }),
            keccak256(abi.encode(88))
        );

        // check that it reverts
        vm.expectRevert(Nft.InvalidVestingParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: 500}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 3001 days, amount: 0}),
                lockLpParams: Nft.LockLpParams({amount: 100, price: 0}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_RevertIf_InvalidRefundEndTimestampIsSmallerThanCurrentTimestamp() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](2);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});
        categories[1] = Nft.Category({price: 2 ether, supply: 200, merkleRoot: bytes32(0)});

        // check that it reverts
        skip(1 days);
        vm.expectRevert(Nft.InvalidRefundParams.selector);
        launchpad.create(
            BatonLaunchpad.CreateParams({
                name: "name",
                symbol: "symbol",
                categories: categories,
                maxMintSupply: 3000,
                royaltyRate: 0,
                refundParams: Nft.RefundParams({mintEndTimestamp: uint64(block.timestamp - 1)}),
                vestingParams: Nft.VestingParams({receiver: address(0x123), duration: 5 days, amount: 10}),
                lockLpParams: Nft.LockLpParams({amount: 100, price: 1 ether}),
                yieldFarmParams: Nft.YieldFarmParams({amount: 0, duration: 0 days})
            }),
            keccak256(abi.encode(88))
        );
    }

    function test_setFeeRate_SetsFeeRate() public {
        // set the fee rate
        launchpad.setFeeRate(100);

        // check that the fee rate was set
        assertEq(launchpad.feeRate(), 100);
    }

    function test_RevertIf_setFeeRate_CallerIsNotOwner() public {
        // check that it reverts
        vm.prank(address(0xdead));
        vm.expectRevert(Unauthorized.selector);
        launchpad.setFeeRate(100);
    }

    function test_setNftImplementation_SetsNftImplementation() public {
        // set the nft implementation
        launchpad.setNftImplementation(address(0x123));

        // check that the nft implementation was set
        assertEq(launchpad.nftImplementation(), address(0x123));
    }

    function test_RevertIf_setNftImplementation_CallerIsNotOwner() public {
        // check that it reverts
        vm.prank(address(0xdead));
        vm.expectRevert(Unauthorized.selector);
        launchpad.setNftImplementation(address(0x123));
    }

    function test_withdraw_SendsETHToCaller() public {
        // send some ETH to the launchpad
        deal(address(launchpad), 100 ether);

        // withdraw the ETH
        uint256 balanceBefore = address(this).balance;
        launchpad.withdraw();

        // check that the ETH was sent to the caller
        assertEq(balanceBefore + 100 ether, address(this).balance);
    }

    function test_RevertIf_withdraw_CallerIsNotOwner() public {
        // check that it reverts
        vm.prank(address(0xdead));
        vm.expectRevert(Unauthorized.selector);
        launchpad.withdraw();
    }
}
