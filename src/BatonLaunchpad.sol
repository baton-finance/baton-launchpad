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

    /**
     * @notice Creates a new NFT contract.
     * @param salt The salt used to create the new NFT contract (must be unique).
     * @param name The name of the NFT.
     * @param symbol The symbol of the NFT.
     * @param categories The categories of the NFT.
     * @param maxMintSupply The max mint supply of the NFT.
     * @param refunds Whether or not refunds are enabled.
     * @param vestingParams The vesting params of the NFT.
     * @param lockLpParams The lock LP params of the NFT.
     * @param yieldFarmParams The yield farm params of the NFT.
     * @return nft The address of the newly created NFT contract.
     */
    function create(
        bytes32 salt,
        string memory name,
        string memory symbol,
        Nft.Category[] memory categories,
        uint32 maxMintSupply,
        bool refunds,
        Nft.VestingParams memory vestingParams,
        Nft.LockLpParams memory lockLpParams,
        Nft.YieldFarmParams memory yieldFarmParams
    ) public returns (Nft nft) {
        // deploy the nft
        nft = Nft(payable(nftImplementation.cloneDeterministic(salt)));

        // initialize the nft
        nft.initialize(
            name, symbol, msg.sender, categories, maxMintSupply, refunds, vestingParams, lockLpParams, yieldFarmParams
        );
    }

    /**
     * @notice Sets the NFT implementation.
     * @param _nftImplementation The address of the new NFT implementation.
     */
    function setNftImplementation(address _nftImplementation) public onlyOwner {
        nftImplementation = _nftImplementation;
    }

    /**
     * @notice Sets the fee rate.
     * @param _feeRate The new fee rate.
     */
    function setFeeRate(uint256 _feeRate) public onlyOwner {
        feeRate = _feeRate;
    }
}
