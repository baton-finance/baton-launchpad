// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Nft} from "./Nft.sol";

contract BatonLaunchpad is Ownable {
    using LibClone for address;

    address public nftImplementation;
    uint256 public feeRate;

    constructor(uint256 _feeRate) {
        _initializeOwner(msg.sender);
        feeRate = _feeRate;
    }

    receive() external payable {}

    function create(
        bytes32 salt,
        string memory name,
        string memory symbol,
        Nft.Category[] memory categories,
        uint32 maxMintSupply,
        bool refunds,
        Nft.VestingParams memory vestingParmas,
        Nft.LockLpParams memory lockLpParams,
        Nft.YieldFarmParams memory yieldFarmParams
    ) public returns (Nft nft) {
        // deploy the nft
        nft = Nft(payable(nftImplementation.cloneDeterministic(salt)));

        // initialize the nft
        nft.initialize(
            name, symbol, msg.sender, categories, maxMintSupply, refunds, vestingParmas, lockLpParams, yieldFarmParams
        );
    }

    function setNftImplementation(address _nftImplementation) public onlyOwner {
        nftImplementation = _nftImplementation;
    }

    function setFeeRate(uint256 _feeRate) public onlyOwner {
        feeRate = _feeRate;
    }
}
