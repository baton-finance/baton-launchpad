// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/BatonLaunchpad.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

contract MintHandler is Test {
    Nft private nft;
    BatonLaunchpad private launchpad;

    constructor(Nft _nft, BatonLaunchpad _launchpad) {
        nft = _nft;
        launchpad = _launchpad;
    }

    function handleMint(uint64 amount) external {
        vm.startPrank(msg.sender);

        uint32 maxMintSupply = nft.maxMintSupply();
        amount = nft.totalSupply() < 2000
            ? uint64(bound(amount, 1, maxMintSupply - nft.totalSupply()))
            : uint64(maxMintSupply - nft.totalSupply());

        uint8 categoryIndex = 0;
        uint256 ethAmount = amount * nft.categories(categoryIndex).price;
        uint256 protocolFee = ethAmount * launchpad.feeRate() / 1e18;

        bytes32[] memory merkleProof = new bytes32[](0);
        nft.mint{value: ethAmount + protocolFee}(amount, categoryIndex, merkleProof);

        vm.stopPrank();
    }

    function handleRefund(uint64 startIndex, uint64 amount) external {
        vm.startPrank(msg.sender);

        startIndex = uint64(bound(startIndex, 1, 3_000));
        amount = uint64(bound(amount, 1, 3_000));
        uint256[] memory tokenIds = new uint256[](startIndex);
        for (uint64 i = 0; i < amount; i++) {
            tokenIds[i] = startIndex + amount;
        }

        nft.refund(tokenIds);
        vm.stopPrank();
    }

    function handleVest(uint64 amount) external {
        vm.startPrank(msg.sender);

        amount = uint64(bound(amount, 1, 3_000));
        nft.vest(amount);

        vm.stopPrank();
    }

    function handleLockLp(uint32 amount) external {
        vm.startPrank(msg.sender);

        amount = uint32(bound(amount, 1, 3_000));
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.lockLp(amount, messages);

        vm.stopPrank();
    }

    function handleSeedYieldFarm(uint32 amount) external {
        vm.startPrank(msg.sender);

        amount = uint32(bound(amount, 1, 3_000));
        StolenNftFilterOracle.Message[] memory messages = new StolenNftFilterOracle.Message[](0);
        nft.seedYieldFarm(amount, messages);

        vm.stopPrank();
    }

    function handleSkipTime(uint16 amount) external {
        amount = uint16(bound(amount, 1, 1 days));
        skip(amount);
    }
}

contract InvariantTest is Test {
    address babe = address(0xbabe);
    Nft private nft;

    function setUp() public {
        StolenNftFilterOracle oracle = new StolenNftFilterOracle();
        Caviar caviar = new Caviar(address(oracle));
        BatonFactory batonFactory = new BatonFactory(payable(address(0)), address(caviar), address(this));
        BatonLaunchpad launchpad = new BatonLaunchpad(0);

        // deploy the nft implementation
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 3000, merkleRoot: bytes32(0)});
        nft = new Nft(address(caviar), address(launchpad), address(batonFactory));
        nft.initialize(
            "name",
            "symbol",
            address(this),
            categories,
            3000,
            0,
            Nft.RefundParams({mintEndTimestamp: uint64(block.timestamp + 2 days)}),
            Nft.VestingParams({receiver: address(0x123), duration: 15 days, amount: 200}),
            Nft.LockLpParams({amount: 1000, price: 1 ether}),
            Nft.YieldFarmParams({amount: 100, duration: 1 days})
        );

        MintHandler handler = new MintHandler(nft, launchpad);

        deal(babe, 100_000 ether);
        deal(address(this), 100_000 ether);

        targetContract(address(nft));
        targetContract(address(handler));
        targetSender(address(this));
        targetSender(babe);

        FuzzSelector memory selector = FuzzSelector({addr: address(handler), selectors: new bytes4[](6)});
        selector.selectors[0] = handler.handleMint.selector;
        selector.selectors[1] = handler.handleRefund.selector;
        selector.selectors[2] = handler.handleVest.selector;
        selector.selectors[3] = handler.handleLockLp.selector;
        selector.selectors[4] = handler.handleSeedYieldFarm.selector;
        selector.selectors[5] = handler.handleSkipTime.selector;
        targetSelector(selector);
    }

    // check that if the mint has complete
    // there is always enough eth for the locked lp supply that is left
    function invariant_IfMintCompletedThereIsAlwaysEnoughEthForLockedLp() public {
        if (nft.mintCompleteTimestamp() == 0) return;

        assertGe(address(nft).balance, (nft.lockLpParams().amount - nft.lockedLpSupply()) * nft.lockLpParams().price);
    }
}
